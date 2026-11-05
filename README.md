# Local Services Finder

Flutter client with a Flask API and SQLite database for authentication, saved locations and service-provider discovery.

## Authentication API

No backend or database was present in this app folder. The unrelated Flask projects nearby were not reused. This project now contains a small Flask API that owns account registration, password verification, session refresh, and logout.

### Start the backend

From the project root:

```sh
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.txt
PORT=5001 python3 backend/app.py
```

The backend is running at `http://127.0.0.1:5001` and creates `backend/instance/local_services.sqlite3` on first start. Port 5000 is in use by another local service. The database directory is ignored by Git. Set `LOCAL_SERVICES_DB` to use another SQLite path. For development, `CORS_ORIGINS` defaults to Flutter Web origins on port 5180 and allows GET/POST/PUT/DELETE. Set it to a comma-separated allowlist for a different web origin.

### Location and nearby services setup

The backend uses Google Places for location autocomplete and nearby service searches when `GOOGLE_MAPS_API_KEY` is configured. Without that key, location search and service-specific business discovery use Photon and OpenStreetMap data. OSM results include attribution; ratings, reviews, phone numbers and opening status are shown only when the data source supplies them. OSM coverage differs by service and location, so an empty result is possible.

Google Places and the interactive Google Map require Google Maps Platform billing and APIs enabled. Configure a server-side key for Places/Geocoding and a separate browser key restricted by HTTP referrer for Maps JavaScript:

```sh
export GOOGLE_MAPS_API_KEY='server-side Places and Geocoding key'
PORT=5001 python3 backend/app.py
```

Start Flutter Web with the browser key in the URL (the key must be referrer restricted):

```sh
flutter run -d chrome --web-port 5180 --dart-define=API_BASE_URL=http://127.0.0.1:5001
# Open http://localhost:5180/?maps_key=YOUR_BROWSER_RESTRICTED_KEY
```

Without Google keys, users can search and select locations worldwide through Photon, or choose GPS (coordinates are saved; readable reverse-geocoding needs Google Geocoding). Chrome location access must be allowed for the localhost site and in macOS Location Services.

Nearby discovery first checks active providers in SQLite, then searches Google Places or tagged OSM business data when the local database has no matches. External results are cached in SQLite and linked to the existing provider/request flow. Search starts at the requested radius and expands up to 20 km when needed. No sample provider records or fabricated ratings are included.

### Start Flutter Web in Chrome

In another terminal:

```sh
flutter pub get
flutter run -d chrome --web-port 5180 --dart-define=API_BASE_URL=http://127.0.0.1:5001
```

For a phone or another computer, use the Mac's reachable LAN address for `API_BASE_URL`, bind Flask to `0.0.0.0`, and add the Flutter origin to `CORS_ORIGINS`. Browser secure storage requires a secure context; localhost is treated as secure by browsers, while deployed environments should use HTTPS.

## Authentication routes

- `POST /api/auth/register` — `{full_name, email, password}`; returns a user and access/refresh token pair, or `409` for a duplicate email.
- `POST /api/auth/login` — `{email, password}`; returns a user and token pair or `401` for invalid credentials.
- `GET /api/auth/me` — authenticated profile lookup using an access bearer token.
- `POST /api/auth/refresh` — rotates a refresh token and issues a new access/refresh pair.
- `POST /api/auth/logout` — revokes the presented access/refresh session tokens.
- `GET /api/health` — service health check.

Passwords are hashed with Werkzeug `scrypt`; SQLite stores only the hash. Tokens are high-entropy opaque bearer tokens; the database stores only SHA-256 token hashes, with 15-minute access and 30-day refresh expiry. Refresh tokens rotate on use. Flutter stores the returned tokens with `flutter_secure_storage` and validates the user against `/api/auth/me` on app startup. Web storage uses browser Web Crypto and requires HTTPS or localhost.

The database schema is initialized by the backend and contains `users`, `auth_sessions`, `saved_addresses`, `selected_locations`, `providers` and `service_requests`; no earlier app database or migrations were found. Registration currently requires full name, email and a password of at least eight characters. Email is unique case-insensitively. Mobile number, email verification, password reset, Google/Apple OAuth and profile editing endpoints are not implemented by this authentication API.

## Location and provider routes

All routes below require the same bearer access token used by the app:

- `GET/POST /api/addresses` — list or create saved addresses.
- `PUT/DELETE /api/addresses/<id>` — edit or delete an owned address.
- `POST /api/addresses/<id>/default` — set an owned address as default.
- `GET/PUT /api/location` — restore or persist the selected location.
- `GET /api/location/autocomplete?q=...` — Google Places suggestions when configured, otherwise Photon suggestions.
- `GET /api/location/places/<place_id>` — resolve a Google Place or Photon location selection.
- `GET /api/location/reverse-geocode?latitude=...&longitude=...` — readable GPS address (requires server key).
- `GET /api/providers/nearby?latitude=...&longitude=...&radius=5&category=Electrician&available=true` — nearby local or external business results sorted by distance, optionally filtered by availability.

OpenStreetMap/Photon results can omit business fields that are not present in OSM. Provider cards and details show `© OpenStreetMap contributors` when OSM data is displayed.
- `GET /api/requests` — the signed-in user's persisted service requests.
- `POST /api/requests` — create a request for an active provider.
- `POST /api/requests/<id>/cancel` — cancel an owned pending request.

## Tests

```sh
python3 -m pytest backend/tests -q
flutter analyze
flutter test
```
