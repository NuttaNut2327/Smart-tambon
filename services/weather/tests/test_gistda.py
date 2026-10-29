"""GISTDA disaster cache: answered from the database until it expires; GISTDA is called only on a miss."""

import json
from datetime import UTC, datetime, timedelta

import httpx
import pytest

from app.api import gistda as gistda_api
from app.main import app
from app.providers.base import ProviderError
from app.providers.gistda import GistdaApi
from app.services import gistda
from tests.conftest import ADMIN

KEY = "test-gistda-key"
BBOX = [100.0, 14.0, 100.2, 14.1]
INSIDE = "MULTIPOLYGON(((100 14,100.1 14,100.1 14.1,100 14.1,100 14)))"


def flood(fid, lon):
    ring = [[lon, 14.02], [lon + 0.01, 14.02], [lon + 0.01, 14.03], [lon, 14.03], [lon, 14.02]]
    return {"type": "Feature", "id": fid, "geometry": {"type": "MultiPolygon", "coordinates": [[ring]]},
            "properties": {"tb_tn": "ต.ทดสอบ", "ap_tn": "อ.ทดสอบ", "pv_tn": "จ.ทดสอบ", "tb_idn": 990101,
                           "f_area": 11120.75, "rice_area": None, "population": 0, "building": 3,
                           "_createdBy": "secret-owner", "_updatedAt": "2026-10-22T18:12:30Z"}}


def hotspot(hid, lon, lat):
    return {"type": "Feature", "id": f"m{hid}", "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {"hotspotid": hid, "latitude": lat, "longitude": lon, "acq_date": "2026-10-22T00:00:00",
                           "acq_time": "0506", "confidence": "nominal", "frp": 3.05, "bright_ti4": 333.85,
                           "satellite": "N", "instrument": "VIIRS", "lu_name": None, "tb_idn": 0}}


class Upstream:
    """Fake api-gateway.gistda.or.th: records calls and the API-Key header."""

    def __init__(self, features=(), status=200, number_matched=None):
        self.features = list(features)
        self.status = status
        self.number_matched = number_matched
        self.calls = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.calls.append(request)
        if self.status != 200:
            return httpx.Response(self.status, json={"message": "nope"})
        if "/maps/" in request.url.path:
            if request.url.path.endswith("/9/9/9"):
                return httpx.Response(404, json={"message": "not found"})
            return httpx.Response(200, content=b"\x89PNG-fake", headers={"content-type": "image/png"})
        limit, offset = int(request.url.params["limit"]), int(request.url.params["offset"])
        page = self.features[offset:offset + limit]
        matched = self.number_matched if self.number_matched is not None else len(self.features)
        return httpx.Response(200, headers={"content-type": "application/geo+json"}, json={
            "type": "FeatureCollection", "features": page, "numberMatched": matched, "numberReturned": len(page),
            "timeStamp": "2026-10-23T15:42:46.194Z",
            "links": [{"href": f"https://api-gateway.gistda.or.th/x?api_key={KEY}", "rel": "self"}]})


def make_api(upstream):
    return GistdaApi(transport=httpx.MockTransport(upstream), sleep=lambda _s: None)


def test_flood_miss_then_hit_clips_to_boundary_and_drops_extra_props(db):
    upstream = Upstream([flood("a", 100.02), flood("b", 100.15)])
    api = make_api(upstream)

    first = gistda.get_features(db, api, "flood", 7, BBOX, api_key=KEY, boundary_wkt=INSIDE)
    assert first["cache"] == "miss"
    assert [f["id"] for f in first["features"]] == ["a"], "feature outside the boundary is clipped"
    props = first["features"][0]["properties"]
    assert props["area_sq_m"] == 11120.75 and props["buildings"] == 3.0
    assert props["rice_area_sq_m"] is None, "missing upstream values stay NULL"
    assert "_createdBy" not in props
    assert KEY not in json.dumps(first), "the key echoed in GISTDA links is never passed on"
    assert upstream.calls[0].headers["API-Key"] == KEY
    assert upstream.calls[0].url.params["bbox"] == "100.0000,14.0000,100.2000,14.1000"

    second = gistda.get_features(db, api, "flood", 7, BBOX, api_key=KEY)
    assert second["cache"] == "hit" and second["count"] == 2
    assert len(upstream.calls) == 1, "fresh cache is served from the database"


def test_expired_cache_is_refreshed_and_replaced(db):
    upstream = Upstream([hotspot("h1", 100.05, 14.05)])
    api = make_api(upstream)
    gistda.get_features(db, api, "hotspots", 1, BBOX, api_key=KEY)
    upstream.features = [hotspot("h2", 100.06, 14.06), hotspot("h3", 100.07, 14.07)]

    later = datetime.now(UTC) + timedelta(hours=2)
    result = gistda.get_features(db, api, "hotspots", 1, BBOX, api_key=KEY, now=later)
    assert result["cache"] == "miss"
    assert sorted(f["id"] for f in result["features"]) == ["h2", "h3"]
    assert result["features"][0]["properties"]["acquired_at"] == "2026-10-22T05:06:00+00:00"
    assert result["features"][0]["properties"]["tambon_code"] is None, "GISTDA's 0 means no admin area"
    assert db.query(gistda.GistdaFetch).count() == 1


def test_upstream_failure_serves_stale_copy(db):
    upstream = Upstream([hotspot("h1", 100.05, 14.05)])
    api = make_api(upstream)
    gistda.get_features(db, api, "hotspots", 1, BBOX, api_key=KEY)
    upstream.status = 503

    result = gistda.get_features(db, api, "hotspots", 1, BBOX, api_key=KEY, now=datetime.now(UTC) + timedelta(hours=2))
    assert result["stale"] is True and result["count"] == 1


def test_no_key_and_nothing_cached_raises(db):
    with pytest.raises(gistda.MissingKey):
        gistda.get_features(db, make_api(Upstream()), "flood", 7, BBOX, api_key=None)


def test_paging_stops_at_cap_and_marks_truncated(db, monkeypatch):
    monkeypatch.setitem(gistda.MAX_FEATURES, "hotspots", 3)
    monkeypatch.setattr(gistda, "PAGE_SIZE", 2)
    upstream = Upstream([hotspot(f"h{i}", 100.01 + i / 100, 14.05) for i in range(5)])
    result = gistda.get_features(db, make_api(upstream), "hotspots", 1, BBOX, api_key=KEY)
    assert result["count"] == 3 and result["number_matched"] == 5 and result["truncated"] is True
    assert [c.url.params["offset"] for c in upstream.calls] == ["0", "2"]


def test_rejected_key_is_reported(db):
    from app.providers.gistda import GistdaKeyError

    with pytest.raises(GistdaKeyError):
        gistda.get_features(db, make_api(Upstream(status=401)), "flood", 7, BBOX, api_key="bad")


def test_tiles_cached_in_database(db):
    upstream = Upstream()
    api = make_api(upstream)
    assert gistda.get_tile(db, api, "drought", 7, 6, 50, 29, api_key=KEY) == (b"\x89PNG-fake", "image/png", "miss")
    assert gistda.get_tile(db, api, "drought", 7, 6, 50, 29, api_key=None)[2] == "hit"
    assert gistda.get_tile(db, api, "drought", 7, 9, 9, 9, api_key=KEY)[0] is None, "missing tile is cached as empty"
    assert len(upstream.calls) == 2
    assert upstream.calls[0].url.path.endswith("/maps/dri/7days/tms/6/50/29")


def test_api_requires_admin_and_validates_bbox(client):
    assert client.post("/api/v1/gistda/features", json={"dataset": "flood", "bbox": BBOX}).status_code == 401
    r = client.post("/api/v1/gistda/features", headers=ADMIN, json={"dataset": "flood", "bbox": [0, 0, 1, 1]})
    assert r.status_code == 422


def test_api_features_and_tile_endpoints(client):
    upstream = Upstream([flood("a", 100.02)])
    app.dependency_overrides[gistda_api.get_gistda_api] = lambda: make_api(upstream)
    try:
        r = client.post("/api/v1/gistda/features", headers={**ADMIN, "X-Gistda-Api-Key": KEY},
                        json={"dataset": "flood", "period_days": 7, "bbox": BBOX, "boundary_wkt": INSIDE})
        assert r.status_code == 200
        assert r.json()["count"] == 1 and r.json()["source"] == "GISTDA"

        t = client.get("/api/v1/gistda/tiles/drought/6/50/29", headers={**ADMIN, "X-Gistda-Api-Key": KEY})
        assert t.status_code == 200 and t.headers["content-type"] == "image/png" and t.headers["x-cache"] == "miss"
        assert client.get("/api/v1/gistda/tiles/drought/6/50/29", headers=ADMIN).headers["x-cache"] == "hit"
        flood_tile = client.get("/api/v1/gistda/tiles/flood/6/50/29?period_days=7", headers={**ADMIN, "X-Gistda-Api-Key": KEY})
        assert flood_tile.status_code == 200, "period_days given as a query string is accepted"
        assert upstream.calls[-1].url.path.endswith("/maps/flood/7days/tms/6/50/29")
        assert client.get("/api/v1/gistda/tiles/flood/6/50/29?period_days=5", headers=ADMIN).status_code == 422

        missing = client.post("/api/v1/gistda/features", headers=ADMIN, json={"dataset": "hotspots", "bbox": BBOX})
        assert missing.status_code == 503 and missing.json()["detail"]["code"] == "gistda_key_missing"

        assert client.get("/api/v1/gistda/status", headers=ADMIN).json()["features"] == 1
    finally:
        app.dependency_overrides.clear()


def test_provider_error_type():
    assert issubclass(gistda.GistdaKeyError, ProviderError)
