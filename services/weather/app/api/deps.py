import secrets

from fastapi import Depends, Header, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import get_db
from app.models import WeatherLocation


def require_admin(
    x_api_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> None:
    expected = get_settings().admin_api_key
    if not expected:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "admin API disabled: WEATHER_ADMIN_API_KEY not set")
    supplied = x_api_key
    if not supplied and authorization and authorization.lower().startswith("bearer "):
        supplied = authorization[7:]
    if not supplied or not secrets.compare_digest(supplied, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or missing API key",
                            headers={"WWW-Authenticate": "Bearer"})


def nearest_locations(db: Session, lat: float, lon: float, limit: int = 1, max_km: float | None = None):
    pt = func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)
    dist = func.ST_DistanceSphere(WeatherLocation.geom, pt)
    stmt = (
        select(WeatherLocation, (dist / 1000.0).label("km"))
        .where(WeatherLocation.is_active.is_(True))
        .order_by(WeatherLocation.geom.op("<->")(pt))
        .limit(limit)
    )
    rows = db.execute(stmt).all()
    if max_km is not None:
        rows = [r for r in rows if r.km <= max_km]
    return rows


def resolve_location(
    location_id: int | None = Query(default=None, description="Location id"),
    code: str | None = Query(default=None, description="Location code, e.g. nakhon-sawan"),
    lat: float | None = Query(default=None, ge=-90, le=90, description="Use nearest location to this GPS point"),
    lon: float | None = Query(default=None, ge=-180, le=180),
    db: Session = Depends(get_db),
) -> WeatherLocation:
    loc = None
    if location_id is not None:
        loc = db.get(WeatherLocation, location_id)
    elif code:
        loc = db.scalar(select(WeatherLocation).where(WeatherLocation.code == code))
    elif lat is not None and lon is not None:
        rows = nearest_locations(db, lat, lon, 1)
        loc = rows[0][0] if rows else None
    else:
        raise HTTPException(422, "provide location_id, code, or lat+lon")
    if loc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "location not found")
    return loc
