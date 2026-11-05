"""Local Services Finder authentication API backed by SQLite."""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import secrets
import sqlite3
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path
from typing import Any, Callable

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash


BASE_DIR = Path(__file__).resolve().parent
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
ACCESS_TTL = timedelta(minutes=15)
REFRESH_TTL = timedelta(days=30)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_app(test_config: dict[str, Any] | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_mapping(
        DATABASE_PATH=os.environ.get(
            "LOCAL_SERVICES_DB", str(BASE_DIR / "instance" / "local_services.sqlite3")
        ),
        CORS_ORIGINS=os.environ.get(
            "CORS_ORIGINS",
            "http://localhost:5180,http://127.0.0.1:5180",
        ),
        GOOGLE_MAPS_API_KEY=os.environ.get("GOOGLE_MAPS_API_KEY", ""),
    )
    if test_config:
        app.config.update(test_config)

    origins = app.config["CORS_ORIGINS"]
    if isinstance(origins, str):
        origins = [origin.strip() for origin in origins.split(",") if origin.strip()]
    CORS(app, resources={r"/api/*": {"origins": origins}}, allow_headers=["Content-Type", "Authorization"], methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])

    def connect_db() -> sqlite3.Connection:
        path = Path(app.config["DATABASE_PATH"])
        path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def init_db() -> None:
        connection = connect_db()
        try:
            with connection:
                connection.executescript(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        full_name TEXT NOT NULL,
                        email TEXT NOT NULL COLLATE NOCASE UNIQUE,
                        password_hash TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS auth_sessions (
                        token_hash TEXT PRIMARY KEY,
                        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        token_type TEXT NOT NULL CHECK(token_type IN ('access', 'refresh')),
                        expires_at TEXT NOT NULL,
                        revoked INTEGER NOT NULL DEFAULT 0,
                        created_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id);
                    CREATE INDEX IF NOT EXISTS idx_auth_sessions_expiry ON auth_sessions(expires_at);
                    CREATE TABLE IF NOT EXISTS saved_addresses (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        label TEXT NOT NULL CHECK(label IN ('Home','Work','Other')),
                        house_number TEXT NOT NULL DEFAULT '',
                        street TEXT NOT NULL DEFAULT '',
                        area TEXT NOT NULL DEFAULT '',
                        city TEXT NOT NULL,
                        state TEXT NOT NULL DEFAULT '',
                        postal_code TEXT NOT NULL DEFAULT '',
                        formatted_address TEXT NOT NULL,
                        latitude REAL NOT NULL,
                        longitude REAL NOT NULL,
                        place_id TEXT,
                        is_default INTEGER NOT NULL DEFAULT 0,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS idx_saved_addresses_user ON saved_addresses(user_id);
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_addresses_default
                        ON saved_addresses(user_id) WHERE is_default=1;
                    CREATE TABLE IF NOT EXISTS selected_locations (
                        user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                        address_id INTEGER REFERENCES saved_addresses(id) ON DELETE SET NULL,
                        formatted_address TEXT NOT NULL,
                        city TEXT NOT NULL DEFAULT '',
                        state TEXT NOT NULL DEFAULT '',
                        postal_code TEXT NOT NULL DEFAULT '',
                        latitude REAL NOT NULL,
                        longitude REAL NOT NULL,
                        source TEXT NOT NULL CHECK(source IN ('gps','manual','saved')),
                        updated_at TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS providers (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        category TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT '',
                        latitude REAL NOT NULL,
                        longitude REAL NOT NULL,
                        address TEXT NOT NULL,
                        image_url TEXT,
                        rating REAL,
                        review_count INTEGER,
                        price TEXT,
                        is_verified INTEGER NOT NULL DEFAULT 0,
                        is_available INTEGER NOT NULL DEFAULT 0,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        external_source TEXT,
                        external_id TEXT,
                        phone TEXT,
                        open_now INTEGER,
                        created_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS idx_providers_category_active
                        ON providers(category,is_active);
                    CREATE TABLE IF NOT EXISTS provider_search_cache (
                        cache_key TEXT PRIMARY KEY,
                        payload TEXT NOT NULL,
                        expires_at TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS service_requests (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        provider_id INTEGER REFERENCES providers(id) ON DELETE SET NULL,
                        provider_name TEXT NOT NULL,
                        category TEXT NOT NULL,
                        service TEXT NOT NULL,
                        issue TEXT NOT NULL,
                        preferred_date TEXT NOT NULL,
                        preferred_time TEXT NOT NULL,
                        location TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Accepted','Rejected','Completed','Cancelled')),
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS idx_service_requests_user ON service_requests(user_id,created_at);
                    """
                )
                provider_columns = {row[1] for row in connection.execute("PRAGMA table_info(providers)")}
                if "is_available" not in provider_columns:
                    connection.execute("ALTER TABLE providers ADD COLUMN is_available INTEGER NOT NULL DEFAULT 0")
                for column, definition in (("external_source", "TEXT"), ("external_id", "TEXT"), ("phone", "TEXT"), ("open_now", "INTEGER")):
                    if column not in provider_columns:
                        connection.execute(f"ALTER TABLE providers ADD COLUMN {column} {definition}")
                connection.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_providers_external ON providers(external_source,external_id) WHERE external_source IS NOT NULL")
        finally:
            connection.close()

    app.extensions["local_services_connect_db"] = connect_db
    app.extensions["local_services_init_db"] = init_db
    init_db()

    @app.teardown_appcontext
    def close_db(_error: BaseException | None) -> None:
        db = g.pop("db", None)
        if db is not None:
            db.close()

    def db() -> sqlite3.Connection:
        if "db" not in g:
            g.db = connect_db()
        return g.db

    def public_user(row: sqlite3.Row) -> dict[str, Any]:
        return {"id": row["id"], "full_name": row["full_name"], "email": row["email"]}

    def issue_token_pair(user_id: int) -> dict[str, str]:
        now = utc_now()
        pair: dict[str, str] = {}
        connection = db()
        for kind, ttl in (("access", ACCESS_TTL), ("refresh", REFRESH_TTL)):
            raw = secrets.token_urlsafe(48)
            connection.execute(
                "INSERT INTO auth_sessions(token_hash,user_id,token_type,expires_at,created_at) VALUES(?,?,?,?,?)",
                (token_hash(raw), user_id, kind, (now + ttl).isoformat(), now.isoformat()),
            )
            pair[f"{kind}_token"] = raw
        connection.commit()
        return pair

    def json_error(message: str, status: int):
        return jsonify({"error": message}), status

    def google_json(url: str, *, method: str = "GET", body: dict[str, Any] | None = None, field_mask: str | None = None):
        key = app.config["GOOGLE_MAPS_API_KEY"]
        if not key:
            return None
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
            headers["X-Goog-Api-Key"] = key
        if field_mask:
            headers["X-Goog-FieldMask"] = field_mask
        if body is None and "key=" not in url:
            joiner = "&" if "?" in url else "?"
            url = f"{url}{joiner}key={urllib.parse.quote(key)}"
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=8) as response:
                payload = json.loads(response.read())
            return payload
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            raise RuntimeError("Google Maps service request failed. Check API enablement, key restrictions and network access.") from error

    def photon_json(url: str):
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "LocalServicesFinder/1.0 (location search)"})
        try:
            with urllib.request.urlopen(req, timeout=12) as response:
                return json.loads(response.read())
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            raise RuntimeError("OpenStreetMap Photon location search is temporarily unavailable.") from error

    SERVICE_SEARCH_TERMS = {
        "Electrician": "electrician electrical contractor",
        "Plumber": "plumber plumbing service",
        "Carpenter": "carpenter carpentry service",
        "AC Repair": "air conditioning repair HVAC service",
        "Home Cleaning": "home cleaning service",
        "Painting": "house painting contractor",
        "Appliance Repair": "home appliance repair service",
    }

    def google_provider_search(category: str, latitude: float, longitude: float, radius_km: float):
        if not app.config["GOOGLE_MAPS_API_KEY"]:
            return None
        payload = google_json(
            "https://places.googleapis.com/v1/places:searchText",
            method="POST",
            body={"textQuery": SERVICE_SEARCH_TERMS[category], "languageCode": "en",
                  "locationBias": {"circle": {"center": {"latitude": latitude, "longitude": longitude}, "radius": radius_km * 1000}},
                  "maxResultCount": 20},
            field_mask="places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.nationalPhoneNumber,places.currentOpeningHours.openNow",
        ) or {}
        found = []
        for place in payload.get("places", []):
            location = place.get("location", {})
            name = place.get("displayName", {}).get("text")
            if not name or "latitude" not in location or "longitude" not in location:
                continue
            found.append({"source": "google", "external_id": place["id"], "name": name,
                "category": category, "description": "", "latitude": location["latitude"],
                "longitude": location["longitude"], "address": place.get("formattedAddress", ""),
                "image_url": None, "rating": place.get("rating"),
                "review_count": place.get("userRatingCount"), "price": None,
                "is_verified": False, "is_available": False,
                "phone": place.get("nationalPhoneNumber"),
                "open_now": place.get("currentOpeningHours", {}).get("openNow")})
        return found

    def osm_provider_search(category: str, latitude: float, longitude: float, radius_km: float):
        # Photon search-as-you-type geocoding data can also return nearby POIs
        # filtered by OSM service tags, avoiding bulk Overpass requests.
        tags = {
            "Electrician": ["craft:electrician", "shop:electrical"],
            "Plumber": ["craft:plumber", "shop:plumbing"],
            "Carpenter": ["craft:carpenter", "craft:joiner"],
            "AC Repair": ["craft:hvac", "shop:air_conditioning"],
            "Home Cleaning": ["craft:cleaning", "office:cleaning"],
            "Painting": ["craft:painter", "craft:painting"],
            "Appliance Repair": ["shop:appliance_repair"],
        }[category]
        params = [("lat", str(latitude)), ("lon", str(longitude)), ("radius", str(radius_km)), ("limit", "30")]
        params.extend(("osm_tag", tag) for tag in tags)
        payload = photon_json("https://photon.komoot.io/reverse?" + urllib.parse.urlencode(params))
        results = []
        for item in payload.get("features", []):
            props = item.get("properties", {})
            name = props.get("name")
            coords = item.get("geometry", {}).get("coordinates", [])
            if not name or len(coords) != 2:
                continue
            extra = props.get("extra", {})
            address = ", ".join(filter(None, [props.get("housenumber"), props.get("street"), props.get("locality"), props.get("city") or props.get("district"), props.get("postcode")]))
            results.append({"source": "osm", "external_id": f"{props.get('osm_type')}/{props.get('osm_id')}", "name": name,
                "category": category, "description": "", "latitude": coords[1], "longitude": coords[0],
                "address": address, "image_url": None,
                "rating": None, "review_count": None, "price": None, "is_verified": False,
                "is_available": False, "phone": extra.get("phone") or extra.get("contact:phone"),
                "open_now": None})
        return results

    def cache_external_providers(category: str, latitude: float, longitude: float, radius_km: float):
        cache_key = f"{category}:{latitude:.3f}:{longitude:.3f}:{radius_km:g}"
        cached = db().execute("SELECT payload FROM provider_search_cache WHERE cache_key=? AND expires_at>?", (cache_key, utc_now().isoformat())).fetchone()
        if cached:
            return json.loads(cached["payload"])
        try:
            results = google_provider_search(category, latitude, longitude, radius_km)
            if not results:
                results = osm_provider_search(category, latitude, longitude, radius_km)
        except RuntimeError as primary_error:
            if not app.config["GOOGLE_MAPS_API_KEY"]:
                raise
            # Try OSM if the configured Google integration is unavailable.
            try:
                results = osm_provider_search(category, latitude, longitude, radius_km)
            except RuntimeError as fallback_error:
                raise RuntimeError(f"Provider search failed: {primary_error} {fallback_error}") from fallback_error
        now = utc_now()
        connection = db()
        for item in results:
            connection.execute("""INSERT INTO providers(name,category,description,latitude,longitude,address,image_url,rating,review_count,price,is_verified,is_available,is_active,external_source,external_id,phone,open_now,created_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,0,0,1,?,?,?,?,?) ON CONFLICT(external_source,external_id) WHERE external_source IS NOT NULL DO UPDATE SET name=excluded.name,category=excluded.category,latitude=excluded.latitude,longitude=excluded.longitude,address=excluded.address,rating=excluded.rating,review_count=excluded.review_count,phone=excluded.phone,open_now=excluded.open_now,is_active=1""",
                (item["name"], category, "", item["latitude"], item["longitude"], item["address"], None, item["rating"], item["review_count"], None, item["source"], item["external_id"], item["phone"], None if item["open_now"] is None else int(item["open_now"]), now.isoformat()))
        connection.execute("INSERT OR REPLACE INTO provider_search_cache(cache_key,payload,expires_at) VALUES(?,?,?)", (cache_key,json.dumps(results), (now+timedelta(hours=6)).isoformat()))
        connection.commit()
        return results

    def address_json(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"], "label": row["label"], "house_number": row["house_number"],
            "street": row["street"], "area": row["area"], "city": row["city"],
            "state": row["state"], "postal_code": row["postal_code"],
            "formatted_address": row["formatted_address"], "latitude": row["latitude"],
            "longitude": row["longitude"], "place_id": row["place_id"],
            "is_default": bool(row["is_default"]),
        }

    def location_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
        if row is None:
            return None
        return {
            "address_id": row["address_id"], "formatted_address": row["formatted_address"],
            "city": row["city"], "state": row["state"], "postal_code": row["postal_code"],
            "latitude": row["latitude"], "longitude": row["longitude"], "source": row["source"],
        }

    def service_request_json(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"], "provider_id": row["provider_id"],
            "provider_name": row["provider_name"], "category": row["category"],
            "service": row["service"], "issue": row["issue"],
            "date": row["preferred_date"], "time": row["preferred_time"],
            "location": row["location"], "status": row["status"],
            "created_at": row["created_at"],
        }

    def parse_google_address(payload: dict[str, Any]) -> dict[str, Any]:
        result = payload.get("result", payload)
        location = result.get("location") or result.get("geometry", {}).get("location", {})
        address_components = result.get("addressComponents") or result.get("address_components", [])
        components: dict[str, str] = {}
        for component in address_components:
            for component_type in component.get("types", []):
                components.setdefault(component_type, component.get("longText") or component.get("long_name", ""))
        city = components.get("locality") or components.get("postal_town") or components.get("administrative_area_level_2", "")
        return {
            "place_id": result.get("id") or result.get("place_id"),
            "formatted_address": result.get("formattedAddress") or result.get("formatted_address", ""),
            "latitude": location.get("latitude", location.get("lat")),
            "longitude": location.get("longitude", location.get("lng")),
            "house_number": components.get("street_number", ""),
            "street": components.get("route", ""),
            "area": components.get("sublocality_level_1") or components.get("neighborhood", ""),
            "city": city,
            "state": components.get("administrative_area_level_1", ""),
            "postal_code": components.get("postal_code", ""),
        }

    def geocode_address(payload: dict[str, Any]) -> dict[str, Any] | None:
        address = str(payload.get("formatted_address", "")).strip() or ", ".join(
            part for part in [payload.get("house_number"), payload.get("street"), payload.get("area"), payload.get("city"), payload.get("state"), payload.get("postal_code")] if str(part or "").strip()
        )
        if not app.config["GOOGLE_MAPS_API_KEY"]:
            return None
        query = urllib.parse.urlencode({"address": address})
        result = google_json(f"https://maps.googleapis.com/maps/api/geocode/json?{query}")
        if not result or result.get("status") != "OK" or not result.get("results"):
            return None
        return parse_google_address(result["results"][0])

    def authenticated(handler: Callable[..., Any]) -> Callable[..., Any]:
        @wraps(handler)
        def wrapper(*args: Any, **kwargs: Any):
            auth_header = request.headers.get("Authorization", "")
            scheme, _, raw = auth_header.partition(" ")
            if scheme.lower() != "bearer" or not raw:
                return json_error("Authentication required.", 401)
            session = db().execute(
                "SELECT s.*,u.id AS uid,u.full_name,u.email FROM auth_sessions s "
                "JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.token_type='access'",
                (token_hash(raw),),
            ).fetchone()
            if (
                session is None
                or session["revoked"]
                or datetime.fromisoformat(session["expires_at"]) <= utc_now()
            ):
                return json_error("Session is invalid or expired. Please sign in again.", 401)
            g.current_user = {
                "id": session["uid"],
                "full_name": session["full_name"],
                "email": session["email"],
            }
            g.access_token_hash = token_hash(raw)
            return handler(*args, **kwargs)

        return wrapper

    @app.post("/api/auth/register")
    def register():
        payload = request.get_json(silent=True) or {}
        full_name = str(payload.get("full_name", "")).strip()
        email = str(payload.get("email", "")).strip().lower()
        password = payload.get("password", "")
        if len(full_name) < 2:
            return json_error("Enter your full name.", 400)
        if not EMAIL_RE.fullmatch(email):
            return json_error("Enter a valid email address.", 400)
        if not isinstance(password, str) or len(password) < 8:
            return json_error("Password must be at least 8 characters.", 400)
        try:
            cursor = db().execute(
                "INSERT INTO users(full_name,email,password_hash,created_at) VALUES(?,?,?,?)",
                (full_name, email, generate_password_hash(password, method="scrypt"), utc_now().isoformat()),
            )
            db().commit()
        except sqlite3.IntegrityError:
            db().rollback()
            return json_error("An account with this email already exists.", 409)
        user = db().execute("SELECT * FROM users WHERE id=?", (cursor.lastrowid,)).fetchone()
        return jsonify({**issue_token_pair(user["id"]), "user": public_user(user)}), 201

    @app.post("/api/auth/login")
    def login():
        payload = request.get_json(silent=True) or {}
        email = str(payload.get("email", "")).strip().lower()
        password = payload.get("password", "")
        if not EMAIL_RE.fullmatch(email) or not isinstance(password, str) or not password:
            return json_error("Enter a valid email address and password.", 400)
        user = db().execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
        if user is None or not check_password_hash(user["password_hash"], password):
            return json_error("Invalid email or password.", 401)
        return jsonify({**issue_token_pair(user["id"]), "user": public_user(user)})

    @app.post("/api/auth/refresh")
    def refresh():
        payload = request.get_json(silent=True) or {}
        raw = payload.get("refresh_token", "")
        if not isinstance(raw, str) or not raw:
            return json_error("Refresh token is required.", 401)
        session = db().execute(
            "SELECT * FROM auth_sessions WHERE token_hash=? AND token_type='refresh'",
            (token_hash(raw),),
        ).fetchone()
        if (
            session is None
            or session["revoked"]
            or datetime.fromisoformat(session["expires_at"]) <= utc_now()
        ):
            return json_error("Session is invalid or expired. Please sign in again.", 401)
        rotated = db().execute(
            "UPDATE auth_sessions SET revoked=1 WHERE token_hash=? AND revoked=0",
            (token_hash(raw),),
        )
        if rotated.rowcount != 1:
            db().rollback()
            return json_error("Session is invalid or expired. Please sign in again.", 401)
        db().commit()
        result = issue_token_pair(session["user_id"])
        user = db().execute("SELECT * FROM users WHERE id=?", (session["user_id"],)).fetchone()
        return jsonify({**result, "user": public_user(user)})

    @app.get("/api/auth/me")
    @authenticated
    def me():
        return jsonify({"user": g.current_user})

    @app.get("/api/addresses")
    @authenticated
    def list_addresses():
        rows = db().execute(
            "SELECT * FROM saved_addresses WHERE user_id=? ORDER BY is_default DESC,created_at DESC",
            (g.current_user["id"],),
        ).fetchall()
        return jsonify({"addresses": [address_json(row) for row in rows]})

    @app.post("/api/addresses")
    @authenticated
    def create_address():
        payload = request.get_json(silent=True) or {}
        label = str(payload.get("label", "Other")).strip().title()
        if label not in {"Home", "Work", "Other"}:
            return json_error("Address label must be Home, Work or Other.", 400)
        if not str(payload.get("city", "")).strip():
            return json_error("City is required.", 400)
        address = payload
        latitude, longitude = payload.get("latitude"), payload.get("longitude")
        if latitude is None or longitude is None:
            try:
                geocoded = geocode_address(payload)
            except RuntimeError as error:
                return json_error(str(error), 502)
            if geocoded is None:
                return json_error("Coordinates are required. Add a Google Maps API key to geocode addresses, or enter latitude and longitude manually.", 400)
            address = {**payload, **geocoded}
            latitude, longitude = address.get("latitude"), address.get("longitude")
        try:
            latitude, longitude = float(latitude), float(longitude)
        except (TypeError, ValueError):
            return json_error("Enter valid latitude and longitude coordinates.", 400)
        if not math.isfinite(latitude) or not math.isfinite(longitude) or not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
            return json_error("Latitude or longitude is out of range.", 400)
        formatted = str(address.get("formatted_address", "")).strip() or ", ".join(
            part for part in [address.get("house_number"), address.get("street"), address.get("area"), address.get("city"), address.get("state"), address.get("postal_code")] if str(part or "").strip()
        )
        if not formatted:
            return json_error("Enter an address.", 400)
        connection = db()
        user_id = g.current_user["id"]
        make_default = bool(payload.get("is_default")) or connection.execute(
            "SELECT 1 FROM saved_addresses WHERE user_id=? LIMIT 1", (user_id,)
        ).fetchone() is None
        if make_default:
            connection.execute("UPDATE saved_addresses SET is_default=0 WHERE user_id=?", (user_id,))
        now = utc_now().isoformat()
        cursor = connection.execute(
            "INSERT INTO saved_addresses(user_id,label,house_number,street,area,city,state,postal_code,formatted_address,latitude,longitude,place_id,is_default,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (user_id,label,str(address.get("house_number", "")).strip(),str(address.get("street", "")).strip(),str(address.get("area", "")).strip(),str(address.get("city", "")).strip(),str(address.get("state", "")).strip(),str(address.get("postal_code", "")).strip(),formatted,latitude,longitude,address.get("place_id"),int(make_default),now,now),
        )
        connection.commit()
        saved = connection.execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (cursor.lastrowid,user_id)).fetchone()
        return jsonify({"address": address_json(saved)}), 201

    @app.put("/api/addresses/<int:address_id>")
    @authenticated
    def update_address(address_id: int):
        payload = request.get_json(silent=True) or {}
        user_id = g.current_user["id"]
        existing = db().execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
        if existing is None:
            return json_error("Saved address not found.", 404)
        merged = {**address_json(existing), **payload}
        label = str(merged.get("label", "Other")).strip().title()
        if label not in {"Home", "Work", "Other"} or not str(merged.get("city", "")).strip():
            return json_error("Choose a valid label and enter a city.", 400)
        address_fields = ("house_number", "street", "area", "city", "state", "postal_code", "formatted_address")
        address_changed = any(key in payload and str(payload[key] or "").strip() != str(address_json(existing).get(key) or "").strip() for key in address_fields)
        if address_changed and not ("latitude" in payload and "longitude" in payload):
            parts = [merged.get(key) for key in ("house_number", "street", "area", "city", "state", "postal_code")]
            merged["formatted_address"] = str(payload.get("formatted_address", "")).strip() or ", ".join(str(part).strip() for part in parts if str(part or "").strip())
            geocoded = geocode_address(merged)
            if geocoded is not None and geocoded.get("latitude") is not None and geocoded.get("longitude") is not None:
                merged.update(geocoded)
            elif "latitude" not in payload or "longitude" not in payload:
                return json_error("Address text changed. Add a Google Maps geocoding key or supply updated latitude and longitude.", 400)
        try:
            latitude, longitude = float(merged["latitude"]), float(merged["longitude"])
        except (KeyError, TypeError, ValueError):
            return json_error("Enter valid latitude and longitude coordinates.", 400)
        if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
            return json_error("Latitude or longitude is out of range.", 400)
        formatted = str(merged.get("formatted_address", "")).strip() or ", ".join(
            part for part in [merged.get("house_number"), merged.get("street"), merged.get("area"), merged.get("city"), merged.get("state"), merged.get("postal_code")] if str(part or "").strip()
        )
        connection = db()
        make_default = bool(merged.get("is_default"))
        if make_default:
            connection.execute("UPDATE saved_addresses SET is_default=0 WHERE user_id=?", (user_id,))
        connection.execute(
            "UPDATE saved_addresses SET label=?,house_number=?,street=?,area=?,city=?,state=?,postal_code=?,formatted_address=?,latitude=?,longitude=?,place_id=?,is_default=?,updated_at=? WHERE id=? AND user_id=?",
            (label,str(merged.get("house_number", "")),str(merged.get("street", "")),str(merged.get("area", "")),str(merged.get("city", "")),str(merged.get("state", "")),str(merged.get("postal_code", "")),formatted,latitude,longitude,merged.get("place_id"),int(make_default),utc_now().isoformat(),address_id,user_id),
        )
        connection.commit()
        updated = connection.execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
        connection.execute(
            "UPDATE selected_locations SET formatted_address=?,city=?,state=?,postal_code=?,latitude=?,longitude=? WHERE user_id=? AND address_id=?",
            (formatted, str(merged.get("city", "")), str(merged.get("state", "")), str(merged.get("postal_code", "")), latitude, longitude, user_id, address_id),
        )
        connection.commit()
        return jsonify({"address": address_json(updated)})

    @app.post("/api/addresses/<int:address_id>/default")
    @authenticated
    def set_default_address(address_id: int):
        connection = db()
        user_id = g.current_user["id"]
        address = connection.execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
        if address is None:
            return json_error("Saved address not found.", 404)
        connection.execute("UPDATE saved_addresses SET is_default=0 WHERE user_id=?", (user_id,))
        connection.execute("UPDATE saved_addresses SET is_default=1,updated_at=? WHERE id=? AND user_id=?", (utc_now().isoformat(),address_id,user_id))
        connection.commit()
        address = connection.execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
        return jsonify({"address": address_json(address)})

    @app.delete("/api/addresses/<int:address_id>")
    @authenticated
    def delete_address(address_id: int):
        connection = db()
        user_id = g.current_user["id"]
        address = connection.execute("SELECT 1 FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
        if address is None:
            return json_error("Saved address not found.", 404)
        connection.execute("UPDATE selected_locations SET address_id=NULL,source='manual' WHERE user_id=? AND address_id=?", (user_id,address_id))
        connection.execute("DELETE FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id))
        connection.commit()
        return jsonify({"message": "Address deleted."})

    @app.get("/api/location")
    @authenticated
    def get_selected_location():
        row = db().execute("SELECT * FROM selected_locations WHERE user_id=?", (g.current_user["id"],)).fetchone()
        if row is None:
            default = db().execute("SELECT * FROM saved_addresses WHERE user_id=? AND is_default=1", (g.current_user["id"],)).fetchone()
            return jsonify({"location": None if default is None else {
                "address_id": default["id"], "formatted_address": default["formatted_address"],
                "city": default["city"], "state": default["state"], "postal_code": default["postal_code"],
                "latitude": default["latitude"], "longitude": default["longitude"], "source": "saved",
            }})
        return jsonify({"location": location_json(row)})

    @app.put("/api/location")
    @authenticated
    def save_selected_location():
        payload = request.get_json(silent=True) or {}
        user_id = g.current_user["id"]
        address_id = payload.get("address_id")
        if address_id is not None:
            address = db().execute("SELECT * FROM saved_addresses WHERE id=? AND user_id=?", (address_id,user_id)).fetchone()
            if address is None:
                return json_error("Saved address not found for this account.", 404)
            location = {
                "address_id": address["id"], "formatted_address": address["formatted_address"],
                "city": address["city"], "state": address["state"], "postal_code": address["postal_code"],
                "latitude": address["latitude"], "longitude": address["longitude"], "source": "saved",
            }
        else:
            location = {key: payload.get(key) for key in ("formatted_address", "city", "state", "postal_code", "latitude", "longitude", "source")}
            location["address_id"] = None
            if location["source"] not in {"gps", "manual"}:
                return json_error("Location source must be gps or manual.", 400)
            try:
                location["latitude"], location["longitude"] = float(location["latitude"]), float(location["longitude"])
            except (TypeError, ValueError):
                return json_error("Select a location with valid coordinates.", 400)
            if not (-90 <= location["latitude"] <= 90) or not (-180 <= location["longitude"] <= 180):
                return json_error("Latitude or longitude is out of range.", 400)
            if not str(location["formatted_address"] or "").strip():
                return json_error("Enter a readable address.", 400)
        db().execute(
            "INSERT INTO selected_locations(user_id,address_id,formatted_address,city,state,postal_code,latitude,longitude,source,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET address_id=excluded.address_id,formatted_address=excluded.formatted_address,city=excluded.city,state=excluded.state,postal_code=excluded.postal_code,latitude=excluded.latitude,longitude=excluded.longitude,source=excluded.source,updated_at=excluded.updated_at",
            (user_id,location["address_id"],location["formatted_address"],location["city"] or "",location["state"] or "",location["postal_code"] or "",location["latitude"],location["longitude"],location["source"],utc_now().isoformat()),
        )
        db().commit()
        return jsonify({"location": location})

    @app.get("/api/location/autocomplete")
    @authenticated
    def location_autocomplete():
        query = request.args.get("q", "").strip()
        if len(query) < 3:
            return jsonify({"suggestions": []})
        if app.config["GOOGLE_MAPS_API_KEY"]:
            try:
                result = google_json("https://places.googleapis.com/v1/places:autocomplete", method="POST", body={"input": query, "languageCode": "en"}, field_mask="suggestions.placePrediction.placeId,suggestions.placePrediction.text.text") or {}
                suggestions = [{"place_id": item["placePrediction"].get("placeId"), "description": item["placePrediction"].get("text", {}).get("text", "")} for item in result.get("suggestions", []) if item.get("placePrediction")]
                if suggestions:
                    return jsonify({"suggestions": suggestions})
            except RuntimeError:
                pass
        location_cache_key = "photon-search:" + query.casefold()
        cached = db().execute("SELECT payload FROM provider_search_cache WHERE cache_key=? AND expires_at>?", (location_cache_key, utc_now().isoformat())).fetchone()
        if cached:
            return jsonify(json.loads(cached["payload"]))
        try:
            results = photon_json("https://photon.komoot.io/api/?" + urllib.parse.urlencode({"q": query, "limit": 6, "lang": "en"}))
        except RuntimeError as error:
            return json_error(str(error), 502)
        suggestions = []
        for feature in results.get("features", []):
            props = feature.get("properties", {})
            coords = feature.get("geometry", {}).get("coordinates", [])
            if len(coords) != 2 or not props.get("name"):
                continue
            description = ", ".join(filter(None, [props.get("name"), props.get("street"), props.get("city") or props.get("district"), props.get("state"), props.get("country")]))
            suggestions.append({"place_id": f"photon:{coords[1]}:{coords[0]}", "description": description})
        payload = {"suggestions": suggestions, "source": "OpenStreetMap via Photon"}
        db().execute("INSERT OR REPLACE INTO provider_search_cache(cache_key,payload,expires_at) VALUES(?,?,?)", (location_cache_key,json.dumps(payload),(utc_now()+timedelta(days=1)).isoformat()))
        db().commit()
        return jsonify(payload)

    @app.get("/api/location/places/<path:place_id>")
    @authenticated
    def location_place_details(place_id: str):
        if place_id.startswith("photon:"):
            try:
                _, lat, lon = place_id.split(":", 2)
                latitude, longitude = float(lat), float(lon)
                item = photon_json("https://photon.komoot.io/reverse?" + urllib.parse.urlencode({"lat": latitude, "lon": longitude}))
                props = item["features"][0].get("properties", {})
                address = ", ".join(filter(None, [props.get("name"), props.get("street"), props.get("city") or props.get("district"), props.get("state"), props.get("country")]))
                return jsonify({"location": {"formatted_address": address, "city": props.get("city") or props.get("district") or "", "state": props.get("state", ""), "postal_code": props.get("postcode", ""), "latitude": latitude, "longitude": longitude, "place_id": place_id}})
            except (RuntimeError, IndexError, KeyError, ValueError) as error:
                return json_error(str(error) or "OpenStreetMap place was not found.", 404)
        if not app.config["GOOGLE_MAPS_API_KEY"]:
            return json_error("Google Places is not configured.", 503)
        url = "https://places.googleapis.com/v1/places/" + urllib.parse.quote(place_id, safe="")
        try:
            result = google_json(url, field_mask="id,formattedAddress,location,addressComponents")
        except RuntimeError as error:
            return json_error(str(error), 502)
        if not result:
            return json_error("Place details were not returned.", 404)
        return jsonify({"location": parse_google_address(result)})

    @app.get("/api/location/reverse-geocode")
    @authenticated
    def reverse_geocode():
        if not app.config["GOOGLE_MAPS_API_KEY"]:
            return json_error("Google Geocoding is not configured. Enter an address manually.", 503)
        try:
            latitude, longitude = float(request.args["latitude"]), float(request.args["longitude"])
        except (KeyError, TypeError, ValueError):
            return json_error("Latitude and longitude are required.", 400)
        if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
            return json_error("Latitude or longitude is out of range.", 400)
        query = urllib.parse.urlencode({"latlng": f"{latitude},{longitude}"})
        try:
            result = google_json(f"https://maps.googleapis.com/maps/api/geocode/json?{query}") or {}
        except RuntimeError as error:
            return json_error(str(error), 502)
        if result.get("status") != "OK" or not result.get("results"):
            return json_error("No address was found for the selected coordinates.", 404)
        return jsonify({"location": parse_google_address(result["results"][0])})

    @app.get("/api/providers/nearby")
    @authenticated
    def nearby_providers():
        try:
            latitude, longitude = float(request.args["latitude"]), float(request.args["longitude"])
            radius = float(request.args.get("radius", "5"))
        except (KeyError, TypeError, ValueError):
            return json_error("Latitude, longitude and a valid radius are required.", 400)
        if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
            return json_error("Latitude or longitude is out of range.", 400)
        if radius not in {1, 3, 5, 10, 20}:
            return json_error("Radius must be 1, 3, 5, 10 or 20 kilometres.", 400)
        category = request.args.get("category", "").strip()
        allowed_categories = {"Electrician", "Plumber", "Carpenter", "AC Repair", "Home Cleaning", "Painting", "Appliance Repair"}
        if category and category not in allowed_categories:
            return json_error("Unknown service category.", 400)
        available = request.args.get("available", "false").lower() == "true"
        rows = db().execute(
            "SELECT * FROM providers WHERE is_active=1 AND (?='' OR category=?) AND (?=0 OR is_available=1)",
            (category,category,int(available)),
        ).fetchall()
        providers = []
        for row in rows:
            lat1, lat2 = math.radians(latitude), math.radians(row["latitude"])
            dlat, dlon = lat2-lat1, math.radians(row["longitude"]-longitude)
            haversine = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
            distance = 6371.0088 * 2 * math.asin(min(1, math.sqrt(haversine)))
            if distance <= radius:
                providers.append({
                    "id": row["id"], "name": row["name"], "category": row["category"],
                    "description": row["description"], "latitude": row["latitude"], "longitude": row["longitude"],
                    "address": row["address"], "image_url": row["image_url"], "rating": row["rating"],
                    "review_count": row["review_count"], "price": row["price"],
                    "is_verified": bool(row["is_verified"]), "is_available": bool(row["is_available"]),
                    "phone": row["phone"] if "phone" in row.keys() else None,
                    "open_now": None if row["open_now"] is None else bool(row["open_now"]),
                    "source": row["external_source"] or "local",
                    "distance_km": round(distance, 2),
                })
        providers.sort(key=lambda provider: provider["distance_km"])
        external_error = None
        if not providers and category and not available:
            for search_radius in sorted({radius, min(10, radius * 2), min(20, radius * 4)}):
                try:
                    external = cache_external_providers(category, latitude, longitude, search_radius)
                except RuntimeError as error:
                    external_error = str(error)
                    external = []
                for item in external:
                    lat1, lat2 = math.radians(latitude), math.radians(float(item["latitude"]))
                    dlat, dlon = lat2-lat1, math.radians(float(item["longitude"])-longitude)
                    haversine = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
                    distance = 6371.0088 * 2 * math.asin(min(1, math.sqrt(haversine)))
                    if distance > search_radius:
                        continue
                    row = db().execute("SELECT id FROM providers WHERE external_source=? AND external_id=?", (item["source"],item["external_id"])).fetchone()
                    if row:
                        providers.append({"id": row["id"], **{key: item.get(key) for key in ("name","category","description","latitude","longitude","address","image_url","rating","review_count","price","is_verified","is_available","phone","open_now")}, "source": item["source"], "distance_km": round(distance,2)})
                if providers:
                    break
            providers.sort(key=lambda provider: provider["distance_km"])
        if not providers and external_error:
            return json_error(external_error, 502)
        return jsonify({"providers": providers, "category": category, "radius_km": radius})

    @app.get("/api/requests")
    @authenticated
    def list_requests():
        rows = db().execute(
            "SELECT * FROM service_requests WHERE user_id=? ORDER BY created_at DESC,id DESC",
            (g.current_user["id"],),
        ).fetchall()
        return jsonify({"requests": [service_request_json(row) for row in rows]})

    @app.post("/api/requests")
    @authenticated
    def create_request():
        payload = request.get_json(silent=True) or {}
        try:
            provider_id = int(payload.get("provider_id"))
        except (TypeError, ValueError):
            return json_error("Choose a valid service provider.", 400)
        provider = db().execute(
            "SELECT * FROM providers WHERE id=? AND is_active=1", (provider_id,)
        ).fetchone()
        if provider is None:
            return json_error("This provider is no longer available.", 404)
        service = str(payload.get("service", "")).strip()
        issue = str(payload.get("issue", "")).strip()
        preferred_date = str(payload.get("date", "")).strip()
        preferred_time = str(payload.get("time", "")).strip()
        location = str(payload.get("location", "")).strip()
        if not all((service, issue, preferred_date, preferred_time, location)):
            return json_error("Service, issue, date, time and location are required.", 400)
        now = utc_now().isoformat()
        connection = db()
        cursor = connection.execute(
            "INSERT INTO service_requests(user_id,provider_id,provider_name,category,service,issue,preferred_date,preferred_time,location,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,'Pending',?,?)",
            (g.current_user["id"],provider_id,provider["name"],provider["category"],service,issue,preferred_date,preferred_time,location,now,now),
        )
        connection.commit()
        row = connection.execute("SELECT * FROM service_requests WHERE id=?", (cursor.lastrowid,)).fetchone()
        return jsonify({"request": service_request_json(row)}), 201

    @app.post("/api/requests/<int:request_id>/cancel")
    @authenticated
    def cancel_request(request_id: int):
        connection = db()
        row = connection.execute(
            "SELECT * FROM service_requests WHERE id=? AND user_id=?",
            (request_id,g.current_user["id"]),
        ).fetchone()
        if row is None:
            return json_error("Service request not found.", 404)
        if row["status"] != "Pending":
            return json_error("Only pending requests can be cancelled.", 409)
        connection.execute(
            "UPDATE service_requests SET status='Cancelled',updated_at=? WHERE id=? AND user_id=?",
            (utc_now().isoformat(),request_id,g.current_user["id"]),
        )
        connection.commit()
        row = connection.execute("SELECT * FROM service_requests WHERE id=?", (request_id,)).fetchone()
        return jsonify({"request": service_request_json(row)})

    @app.post("/api/auth/logout")
    def logout():
        payload = request.get_json(silent=True) or {}
        header = request.headers.get("Authorization", "")
        scheme, _, bearer = header.partition(" ")
        refresh = payload.get("refresh_token", "")
        candidates = [token for token in (bearer if scheme.lower() == "bearer" else "", refresh) if isinstance(token, str) and token]
        if not candidates:
            return jsonify({"message": "Signed out."})
        connection = db()
        found_user_id = None
        for candidate in candidates:
            session = connection.execute(
                "SELECT * FROM auth_sessions WHERE token_hash=?", (token_hash(candidate),)
            ).fetchone()
            if session is not None and not session["revoked"] and datetime.fromisoformat(session["expires_at"]) > utc_now():
                found_user_id = session["user_id"]
                break
        if found_user_id is None:
            return jsonify({"message": "Signed out."})
        for candidate in candidates:
            db().execute(
                "UPDATE auth_sessions SET revoked=1 WHERE token_hash=? AND user_id=?",
                (token_hash(candidate), found_user_id),
            )
        db().commit()
        return jsonify({"message": "Signed out."})

    @app.get("/api/health")
    def health():
        return jsonify({"status": "ok"})

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "5000")), debug=False)
