from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import nearest_locations, require_admin
from app.db import get_db
from app.models import WeatherLocation
from app.schemas import LocationCreate, LocationOut, LocationUpdate, NearestLocationOut
from app.seed import point

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("", response_model=list[LocationOut])
def list_locations(
    province: str | None = None,
    active: bool | None = None,
    limit: int = Query(default=100, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    stmt = select(WeatherLocation).order_by(WeatherLocation.id).limit(limit).offset(offset)
    if province:
        stmt = stmt.where(WeatherLocation.province.ilike(province))
    if active is not None:
        stmt = stmt.where(WeatherLocation.is_active.is_(active))
    return db.scalars(stmt).all()


@router.get("/search", response_model=list[LocationOut])
def search_locations(q: str = Query(min_length=1), limit: int = Query(default=20, ge=1, le=100),
                     db: Session = Depends(get_db)):
    like = f"%{q}%"
    stmt = (
        select(WeatherLocation)
        .where(or_(*(c.ilike(like) for c in (WeatherLocation.name, WeatherLocation.name_th, WeatherLocation.code,
                                             WeatherLocation.province, WeatherLocation.district,
                                             WeatherLocation.subdistrict))))
        .order_by(WeatherLocation.name)
        .limit(limit)
    )
    return db.scalars(stmt).all()


@router.get("/nearest", response_model=list[NearestLocationOut], summary="Lookup locations by GPS")
def nearest(lat: float = Query(ge=-90, le=90), lon: float = Query(ge=-180, le=180),
            limit: int = Query(default=1, ge=1, le=50), max_km: float | None = Query(default=None, gt=0),
            db: Session = Depends(get_db)):
    rows = nearest_locations(db, lat, lon, limit, max_km)
    return [NearestLocationOut(**LocationOut.model_validate(loc).model_dump(), distance_km=round(km, 3))
            for loc, km in rows]


@router.get("/{location_id}", response_model=LocationOut)
def get_location(location_id: int, db: Session = Depends(get_db)):
    loc = db.get(WeatherLocation, location_id)
    if loc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "location not found")
    return loc


@router.post("", response_model=LocationOut, status_code=status.HTTP_201_CREATED,
             dependencies=[Depends(require_admin)])
def create_location(body: LocationCreate, db: Session = Depends(get_db)):
    loc = WeatherLocation(**body.model_dump(), geom=point(body.longitude, body.latitude))
    db.add(loc)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, f"location code '{body.code}' already exists") from None
    db.refresh(loc)
    return loc


@router.patch("/{location_id}", response_model=LocationOut, dependencies=[Depends(require_admin)])
def update_location(location_id: int, body: LocationUpdate, db: Session = Depends(get_db)):
    loc = db.get(WeatherLocation, location_id)
    if loc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "location not found")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(loc, k, v)
    if body.latitude is not None or body.longitude is not None:
        loc.geom = point(loc.longitude, loc.latitude)
    db.commit()
    db.refresh(loc)
    return loc


@router.delete("/{location_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_admin)])
def delete_location(location_id: int, db: Session = Depends(get_db)):
    loc = db.get(WeatherLocation, location_id)
    if loc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "location not found")
    db.delete(loc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
