"""2. Location CRUD, search and GPS lookup."""

from tests.conftest import ADMIN

NEW = {"code": "uthai-thani", "name": "Mueang Uthai Thani", "name_th": "เมืองอุทัยธานี", "province": "Uthai Thani",
       "latitude": 15.3835, "longitude": 100.0246}


def test_seed_is_idempotent(seeded):
    from sqlalchemy import func, select

    from app.models import WeatherLocation
    from app.seed import seed_locations

    seed_locations(seeded)
    assert seeded.scalar(select(func.count()).select_from(WeatherLocation)) == 7


def test_crud_roundtrip(client, seeded):
    assert client.post("/api/v1/locations", json=NEW).status_code == 401
    r = client.post("/api/v1/locations", json=NEW, headers=ADMIN)
    assert r.status_code == 201, r.text
    loc = r.json()
    assert loc["timezone"] == "Asia/Bangkok"

    assert client.post("/api/v1/locations", json=NEW, headers=ADMIN).status_code == 409
    assert client.get(f"/api/v1/locations/{loc['id']}").json()["code"] == "uthai-thani"

    r = client.patch(f"/api/v1/locations/{loc['id']}", json={"latitude": 15.40, "is_active": False}, headers=ADMIN)
    assert r.status_code == 200 and r.json()["latitude"] == 15.40 and r.json()["is_active"] is False

    # geometry follows the coordinates
    near = client.get("/api/v1/locations/nearest", params={"lat": 15.40, "lon": 100.0246, "limit": 1}).json()
    assert near[0]["code"] != "uthai-thani"  # inactive locations are excluded

    assert client.delete(f"/api/v1/locations/{loc['id']}", headers=ADMIN).status_code == 204
    assert client.get(f"/api/v1/locations/{loc['id']}").status_code == 404


def test_validation(client, seeded):
    bad = dict(NEW, latitude=95)
    assert client.post("/api/v1/locations", json=bad, headers=ADMIN).status_code == 422
    bad = dict(NEW, timezone="Mars/Olympus")
    assert client.post("/api/v1/locations", json=bad, headers=ADMIN).status_code == 422
    bad = dict(NEW, code="Has Spaces")
    assert client.post("/api/v1/locations", json=bad, headers=ADMIN).status_code == 422


def test_search(client, seeded):
    assert [x["code"] for x in client.get("/api/v1/locations/search", params={"q": "sawan"}).json()] == ["nakhon-sawan"]
    assert [x["code"] for x in client.get("/api/v1/locations/search", params={"q": "นครสวรรค์"}).json()] == [
        "nakhon-sawan"]
    assert client.get("/api/v1/locations", params={"province": "phuket"}).json()[0]["code"] == "phuket"


def test_nearest_orders_by_distance(client, seeded):
    r = client.get("/api/v1/locations/nearest", params={"lat": 7.1, "lon": 100.4, "limit": 2}).json()
    assert [x["code"] for x in r] == ["hat-yai", "phuket"]
    assert r[0]["distance_km"] < r[1]["distance_km"]
    assert client.get("/api/v1/locations/nearest", params={"lat": 7.1, "lon": 100.4, "max_km": 1}).json() == []
