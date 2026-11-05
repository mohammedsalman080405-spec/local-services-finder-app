import sqlite3

import pytest

from backend.app import create_app


@pytest.fixture()
def client(tmp_path):
    app = create_app(
        {
            "TESTING": True,
            "DATABASE_PATH": str(tmp_path / "auth.sqlite3"),
            "CORS_ORIGINS": ["http://localhost:5180"],
        }
    )
    return app.test_client(), app.config["DATABASE_PATH"]


def register(client, email="salman@example.com", password="strong-pass-1"):
    return client.post(
        "/api/auth/register",
        json={"full_name": "Salman Khan", "email": email, "password": password},
    )


def test_registration_hashes_password_and_returns_session(client):
    http, database = client
    response = register(http)
    assert response.status_code == 201
    payload = response.get_json()
    assert payload["user"]["email"] == "salman@example.com"
    assert payload["access_token"] and payload["refresh_token"]
    with sqlite3.connect(database) as db:
        stored_hash = db.execute("SELECT password_hash FROM users").fetchone()[0]
    assert stored_hash != "strong-pass-1"
    assert stored_hash.startswith("scrypt:")


def test_duplicate_email_is_rejected_case_insensitively(client):
    http, _ = client
    assert register(http).status_code == 201
    response = register(http, email="SALMAN@example.com")
    assert response.status_code == 409
    assert "already exists" in response.get_json()["error"]


def test_login_with_correct_password(client):
    http, _ = client
    register(http)
    response = http.post(
        "/api/auth/login", json={"email": "salman@example.com", "password": "strong-pass-1"}
    )
    assert response.status_code == 200
    assert response.get_json()["user"]["full_name"] == "Salman Khan"


@pytest.mark.parametrize("email,password", [
    ("salman@example.com", "incorrect-pass"),
    ("missing@example.com", "strong-pass-1"),
])
def test_incorrect_or_unregistered_login_is_rejected(client, email, password):
    http, _ = client
    register(http)
    response = http.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 401
    assert response.get_json()["error"] == "Invalid email or password."


def test_profile_restore_refresh_rotation_and_logout_revocation(client):
    http, _ = client
    register_response = register(http)
    original = register_response.get_json()
    headers = {"Authorization": f"Bearer {original['access_token']}"}

    profile = http.get("/api/auth/me", headers=headers)
    assert profile.status_code == 200
    assert profile.get_json()["user"]["email"] == "salman@example.com"

    refreshed = http.post("/api/auth/refresh", json={"refresh_token": original["refresh_token"]})
    assert refreshed.status_code == 200
    current = refreshed.get_json()
    assert current["access_token"] != original["access_token"]
    assert http.post("/api/auth/refresh", json={"refresh_token": original["refresh_token"]}).status_code == 401

    logout = http.post(
        "/api/auth/logout",
        headers={"Authorization": f"Bearer {current['access_token']}"},
        json={"refresh_token": current["refresh_token"]},
    )
    assert logout.status_code == 200
    assert http.get("/api/auth/me", headers={"Authorization": f"Bearer {current['access_token']}"}).status_code == 401
    assert http.post("/api/auth/refresh", json={"refresh_token": current["refresh_token"]}).status_code == 401


def test_web_cors_allows_flutter_dev_origin(client):
    http, _ = client
    response = http.options(
        "/api/auth/login",
        headers={
            "Origin": "http://localhost:5180",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert response.headers["Access-Control-Allow-Origin"] == "http://localhost:5180"
    update = http.options(
        "/api/addresses/1",
        headers={
            "Origin": "http://localhost:5180",
            "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )
    assert update.headers["Access-Control-Allow-Origin"] == "http://localhost:5180"
    assert "PUT" in update.headers["Access-Control-Allow-Methods"]


def test_saved_addresses_are_user_scoped_and_selected_location_persists(client):
    http, _ = client
    first = register(http, email="first@example.com").get_json()
    second = register(http, email="second@example.com").get_json()
    first_headers = {"Authorization": f"Bearer {first['access_token']}"}
    second_headers = {"Authorization": f"Bearer {second['access_token']}"}
    address_response = http.post(
        "/api/addresses",
        headers=first_headers,
        json={
            "label": "Home",
            "house_number": "10",
            "street": "Example Road",
            "area": "Kukatpally",
            "city": "Hyderabad",
            "state": "Telangana",
            "postal_code": "500072",
            "latitude": 17.4948,
            "longitude": 78.3996,
        },
    )
    assert address_response.status_code == 201
    address = address_response.get_json()["address"]
    assert address["is_default"] is True
    address_id = address["id"]

    assert http.get("/api/addresses", headers=second_headers).get_json()["addresses"] == []
    assert http.put("/api/location", headers=second_headers, json={"address_id": address_id}).status_code == 404
    selected = http.put("/api/location", headers=first_headers, json={"address_id": address_id})
    assert selected.status_code == 200
    assert selected.get_json()["location"]["latitude"] == 17.4948
    assert http.get("/api/location", headers=first_headers).get_json()["location"]["address_id"] == address_id

    edited = http.put(
        f"/api/addresses/{address_id}",
        headers=first_headers,
        json={"city": "Miyapur", "formatted_address": "10 Example Road, Miyapur", "latitude": 17.496, "longitude": 78.390},
    )
    assert edited.status_code == 200
    assert edited.get_json()["address"]["city"] == "Miyapur"
    assert http.get("/api/location", headers=first_headers).get_json()["location"]["formatted_address"] == "10 Example Road, Miyapur"
    assert http.delete(f"/api/addresses/{address_id}", headers=first_headers).status_code == 200
    assert http.get("/api/addresses", headers=first_headers).get_json()["addresses"] == []


def test_nearby_providers_are_category_filtered_and_sorted_by_distance(client):
    http, database = client
    session = register(http).get_json()
    headers = {"Authorization": f"Bearer {session['access_token']}"}
    with sqlite3.connect(database) as db:
        db.executemany(
            "INSERT INTO providers(name,category,latitude,longitude,address,is_verified,is_active,created_at) VALUES(?,?,?,?,?,?,?,?)",
            [
                ("Test plumber near", "Plumber", 17.390, 78.487, "Near address", 1, 1, "2026-01-01"),
                ("Test plumber far", "Plumber", 17.420, 78.487, "Far address", 1, 1, "2026-01-01"),
                ("Test electrician", "Electrician", 17.390, 78.487, "Other address", 1, 1, "2026-01-01"),
            ],
        )
    query = "?latitude=17.385&longitude=78.4867&radius=5&category=Plumber&sort=nearest"
    response = http.get("/api/providers/nearby" + query, headers=headers)
    assert response.status_code == 200
    providers = response.get_json()["providers"]
    assert [item["name"] for item in providers] == ["Test plumber near", "Test plumber far"]
    assert providers[0]["distance_km"] < providers[1]["distance_km"]


def test_provider_availability_filter_and_request_history_are_user_scoped(client):
    http, database = client
    customer = register(http, email="customer@example.com").get_json()
    another_customer = register(http, email="another@example.com").get_json()
    headers = {"Authorization": f"Bearer {customer['access_token']}"}
    other_headers = {"Authorization": f"Bearer {another_customer['access_token']}"}
    with sqlite3.connect(database) as db:
        cursor = db.execute(
            "INSERT INTO providers(name,category,latitude,longitude,address,is_available,is_active,created_at) VALUES(?,?,?,?,?,?,?,?)",
            ("Available electrician", "Electrician", 17.385, 78.4867, "Hyderabad", 1, 1, "2026-01-01"),
        )
        provider_id = cursor.lastrowid
    nearby = http.get(
        "/api/providers/nearby?latitude=17.385&longitude=78.4867&radius=5&category=Electrician&available=true",
        headers=headers,
    )
    assert nearby.status_code == 200
    assert nearby.get_json()["providers"][0]["is_available"] is True

    created = http.post(
        "/api/requests",
        headers=headers,
        json={
            "provider_id": provider_id,
            "service": "Electrical Repair",
            "issue": "Switchboard repair",
            "date": "2026-11-06",
            "time": "10:00 AM",
            "location": "Kukatpally, Hyderabad",
        },
    )
    assert created.status_code == 201
    request_id = created.get_json()["request"]["id"]
    assert len(http.get("/api/requests", headers=headers).get_json()["requests"]) == 1
    assert http.get("/api/requests", headers=other_headers).get_json()["requests"] == []
    cancelled = http.post(f"/api/requests/{request_id}/cancel", headers=headers, json={})
    assert cancelled.status_code == 200
    assert cancelled.get_json()["request"]["status"] == "Cancelled"
    assert http.post(f"/api/requests/{request_id}/cancel", headers=headers, json={}).status_code == 409


def test_places_fall_back_to_openstreetmap_without_key_and_manual_location_still_works(client, monkeypatch):
    import backend.app as api

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            if "/reverse?" in self.request.full_url:
                feature = {"type":"Feature","properties":{"name":"OSM Electrical Works","osm_type":"N","osm_id":987,"city":"Hyderabad","street":"Kukatpally","extra":{"phone":"+911234567890"}},"geometry":{"type":"Point","coordinates":[78.40,17.49]}}
            else:
                feature = {"type":"Feature","properties":{"name":"Kukatpally","city":"Hyderabad","state":"Telangana","country":"India","postcode":"500072"},"geometry":{"type":"Point","coordinates":[78.40,17.49]}}
            return ('{"features":[' + __import__("json").dumps(feature) + ']}').encode()

    def fake_urlopen(req, **_kwargs):
        response = FakeResponse()
        response.request = req
        return response

    monkeypatch.setattr(api.urllib.request, "urlopen", fake_urlopen)
    http, _ = client
    session = register(http).get_json()
    headers = {"Authorization": f"Bearer {session['access_token']}"}
    suggestions = http.get("/api/location/autocomplete?q=Kukatpally", headers=headers)
    assert suggestions.status_code == 200
    assert suggestions.get_json()["suggestions"][0]["place_id"] == "photon:17.49:78.4"
    resolved = http.get(
        "/api/location/places/" + suggestions.get_json()["suggestions"][0]["place_id"],
        headers=headers,
    )
    assert resolved.status_code == 200
    assert resolved.get_json()["location"]["latitude"] == 17.49
    providers = http.get(
        "/api/providers/nearby?latitude=17.49&longitude=78.40&radius=5&category=Electrician",
        headers=headers,
    )
    assert providers.status_code == 200
    assert providers.get_json()["providers"][0]["name"] == "OSM Electrical Works"
    assert providers.get_json()["providers"][0]["phone"] == "+911234567890"
    manual = http.put(
        "/api/location",
        headers=headers,
        json={
            "formatted_address": "Manual address, Hyderabad",
            "city": "Hyderabad",
            "latitude": 17.49,
            "longitude": 78.40,
            "source": "manual",
        },
    )
    assert manual.status_code == 200
    assert manual.get_json()["location"]["source"] == "manual"
