"""Database cache in front of the GISTDA Disaster Open API.

A query (dataset + period + bbox) is answered from gistda_fetches/gistda_features until it expires; only then
is GISTDA called again, with the API key the caller (Rails: the อบต. key, else the system key) supplies.
If GISTDA fails and an expired copy exists, the expired copy is served and marked stale. Values GISTDA does
not send stay NULL. Map tiles are cached the same way in gistda_tiles.
"""

import json
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import GistdaFetch, GistdaTile
from app.providers.gistda import PAGE_SIZE, GistdaApi, GistdaKeyError
from app.providers.base import ProviderError
from app.services.locks import lock_key

FEATURE_TTL = {"flood": timedelta(hours=1), "hotspots": timedelta(minutes=30)}
TILE_TTL = {"drought": timedelta(hours=12), "flood": timedelta(hours=1)}
MAX_FEATURES = {"flood": 3_000, "hotspots": 10_000}
KEEP_EXPIRED = timedelta(days=7)


class MissingKey(Exception):
    """Nothing cached and no GISTDA key supplied to fetch it."""


def bbox_key(bbox: list[float]) -> str:
    return ",".join(f"{value:.4f}" for value in bbox)


def get_features(db: Session, api: GistdaApi, dataset: str, period_days: int, bbox: list[float], *,
                 api_key: str | None, boundary_wkt: str | None = None, now: datetime | None = None) -> dict:
    now = now or datetime.now(UTC)
    key = bbox_key(bbox)
    fetch = _latest_fetch(db, dataset, period_days, key)
    cache = "hit"
    if fetch is None or fetch.expires_at <= now:
        if not api_key:
            if fetch is None:
                raise MissingKey("no GISTDA API key supplied and nothing cached for this area")
            cache = "stale"
        else:
            # one refresh per query at a time; a second caller waits and then reads the fresh copy
            db.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": lock_key(f"gistda:{dataset}:{period_days}:{key}")})
            fetch = _latest_fetch(db, dataset, period_days, key)
            if fetch is None or fetch.expires_at <= now:
                try:
                    fetch = _refresh(db, api, dataset, period_days, bbox, key, api_key, now)
                    cache = "miss"
                except GistdaKeyError:
                    db.rollback()
                    raise
                except ProviderError:
                    db.rollback()
                    fetch = _latest_fetch(db, dataset, period_days, key)
                    if fetch is None:
                        raise
                    cache = "stale"
            db.commit()
    return _collection(db, fetch, dataset, period_days, boundary_wkt, cache)


def get_tile(db: Session, api: GistdaApi, layer: str, period_days: int, z: int, x: int, y: int, *,
             api_key: str | None, now: datetime | None = None) -> tuple[bytes | None, str | None, str]:
    now = now or datetime.now(UTC)
    row = db.scalar(select(GistdaTile).where(GistdaTile.layer == layer, GistdaTile.period_days == period_days,
                                             GistdaTile.z == z, GistdaTile.x == x, GistdaTile.y == y))
    if row is not None and row.expires_at > now:
        return row.content, row.content_type, "hit"
    if not api_key:
        if row is None:
            raise MissingKey("no GISTDA API key supplied and tile not cached")
        return row.content, row.content_type, "stale"
    try:
        content, content_type = api.tile(layer, period_days, z, x, y, api_key=api_key)
    except GistdaKeyError:
        raise
    except ProviderError:
        if row is None:
            raise
        return row.content, row.content_type, "stale"
    values = {"layer": layer, "period_days": period_days, "z": z, "x": x, "y": y, "content": content,
              "content_type": content_type, "fetched_at": now, "expires_at": now + TILE_TTL[layer]}
    db.execute(insert(GistdaTile).values(**values).on_conflict_do_update(
        constraint="uq_gistda_tiles", set_={k: values[k] for k in ("content", "content_type", "fetched_at", "expires_at")}))
    db.commit()
    return content, content_type, "miss"


def prune(db: Session, now: datetime | None = None) -> dict:
    """Drop cache rows that expired more than KEEP_EXPIRED ago (expired rows are kept a while as stale fallback)."""
    cutoff = (now or datetime.now(UTC)) - KEEP_EXPIRED
    fetches = db.execute(delete(GistdaFetch).where(GistdaFetch.expires_at < cutoff)).rowcount
    tiles = db.execute(delete(GistdaTile).where(GistdaTile.expires_at < cutoff)).rowcount
    db.commit()
    return {"fetches": fetches, "tiles": tiles}


def _latest_fetch(db: Session, dataset: str, period_days: int, key: str) -> GistdaFetch | None:
    return db.scalar(select(GistdaFetch)
                     .where(GistdaFetch.dataset == dataset, GistdaFetch.period_days == period_days,
                            GistdaFetch.bbox_key == key)
                     .order_by(GistdaFetch.fetched_at.desc()).limit(1))


def _refresh(db: Session, api: GistdaApi, dataset: str, period_days: int, bbox: list[float], key: str,
             api_key: str, now: datetime) -> GistdaFetch:
    max_features = MAX_FEATURES[dataset]
    features: list[dict] = []
    number_matched = None
    timestamp = None
    while True:
        limit = min(PAGE_SIZE, max_features - len(features))
        page = api.features_page(dataset, period_days, bbox=key, limit=limit, offset=len(features), api_key=api_key)
        items = page.get("features") or []
        if number_matched is None:
            number_matched = page.get("numberMatched")
            timestamp = page.get("timeStamp")
        features.extend(items)
        if len(items) < limit or len(features) >= max_features or (number_matched is not None and len(features) >= number_matched):
            break

    slim = [item for item in (_slim(dataset, feature) for feature in features) if item]
    west, south, east, north = bbox
    fetch = GistdaFetch(dataset=dataset, period_days=period_days, bbox_key=key,
                        bbox=f"SRID=4326;POLYGON(({west} {south},{east} {south},{east} {north},{west} {north},{west} {south}))",
                        fetched_at=now, expires_at=now + FEATURE_TTL[dataset],
                        number_matched=number_matched if number_matched is not None else len(features),
                        number_stored=len(slim), truncated=(number_matched or 0) > len(features),
                        data_timestamp=timestamp)
    db.add(fetch)
    db.flush()
    if slim:
        db.execute(text("""
            INSERT INTO gistda_features (fetch_id, feature_id, geom, properties)
            SELECT :fetch_id, f->>'id', ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(f->'geometry'), 4326)), f->'properties'
            FROM jsonb_array_elements(CAST(:features AS jsonb)) AS f
        """), {"fetch_id": fetch.id, "features": json.dumps(slim)})
    db.execute(delete(GistdaFetch).where(GistdaFetch.dataset == dataset, GistdaFetch.period_days == period_days,
                                         GistdaFetch.bbox_key == key, GistdaFetch.id != fetch.id))
    return fetch


def _collection(db: Session, fetch: GistdaFetch, dataset: str, period_days: int, boundary_wkt: str | None,
                cache: str) -> dict:
    sql = "SELECT feature_id, ST_AsGeoJSON(geom, 6), properties FROM gistda_features WHERE fetch_id = :fetch_id"
    params: dict = {"fetch_id": fetch.id}
    if boundary_wkt:
        sql += " AND ST_Intersects(geom, ST_CollectionExtract(ST_MakeValid(ST_GeomFromText(:wkt, 4326)), 3))"
        params["wkt"] = boundary_wkt
    rows = db.execute(text(sql + " ORDER BY id"), params).all()
    features = [{"type": "Feature", "id": feature_id, "geometry": json.loads(geometry), "properties": properties}
                for feature_id, geometry, properties in rows]
    return {
        "type": "FeatureCollection", "dataset": dataset, "period_days": period_days, "source": "GISTDA",
        "cache": cache, "stale": cache == "stale", "fetched_at": fetch.fetched_at.isoformat(),
        "expires_at": fetch.expires_at.isoformat(), "data_timestamp": fetch.data_timestamp,
        "number_matched": fetch.number_matched, "truncated": fetch.truncated, "count": len(features),
        "features": features,
    }


def _slim(dataset: str, feature: dict) -> dict | None:
    geometry = feature.get("geometry")
    props = feature.get("properties") or {}
    if not isinstance(geometry, dict):
        return None
    if dataset == "flood":
        if geometry.get("type") not in ("Polygon", "MultiPolygon"):
            return None
        return {"id": str(feature.get("id") or props.get("_id") or ""), "geometry": geometry, "properties": {
            "kind": "flood", "tambon": props.get("tb_tn"), "amphoe": props.get("ap_tn"), "province": props.get("pv_tn"),
            "tambon_code": _code(props.get("tb_idn")), "area_sq_m": _number(props.get("f_area")),
            "rice_area_sq_m": _number(props.get("rice_area")), "population": _number(props.get("population")),
            "buildings": _number(props.get("building")), "schools": _number(props.get("school")),
            "hospitals": _number(props.get("hospital")), "scenes": props.get("file_name"),
            "updated_at": props.get("_updatedAt"),
        }}
    lon = _number(props.get("longitude"))
    lat = _number(props.get("latitude"))
    if geometry.get("type") != "Point" or lon is None or lat is None:
        return None
    return {"id": str(props.get("hotspotid") or feature.get("id") or ""), "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {
                "kind": "hotspot", "acquired_at": _acquired_at(props), "confidence": props.get("confidence"),
                "frp": _number(props.get("frp")), "brightness": _number(props.get("bright_ti4")),
                "satellite": props.get("satellite"), "instrument": props.get("instrument"),
                "land_use": props.get("lu_name") or None, "village": props.get("village") or None,
                "tambon": props.get("tb_tn") or props.get("tambon_t"), "amphoe": props.get("ap_tn") or props.get("amphoe_t"),
                "province": props.get("pv_tn") or props.get("province_t"), "tambon_code": _code(props.get("tb_idn")),
            }}


def _acquired_at(props: dict) -> str | None:
    """acq_date is the UTC date (at midnight) and acq_time the UTC HHMM of the satellite pass."""
    date = str(props.get("acq_date") or "")[:10]
    hhmm = str(props.get("acq_time") or "").zfill(4)
    try:
        return datetime.strptime(f"{date} {hhmm}", "%Y-%m-%d %H%M").replace(tzinfo=UTC).isoformat()
    except ValueError:
        return None


def _code(value) -> str | None:
    """GISTDA uses 0 for 'no admin area' (e.g. hotspots outside Thailand)."""
    return str(value) if value not in (None, "", 0, "0") else None


def _number(value) -> float | None:
    try:
        return float(value) if value is not None and value != "" else None
    except (TypeError, ValueError):
        return None
