"""GISTDA disaster layers served from the service's database cache (see app.services.gistda).
Admin-only (X-API-Key = WEATHER_ADMIN_API_KEY) because a cache miss calls GISTDA with the key the caller
passes in X-Gistda-Api-Key; that key is never stored or logged."""

from functools import lru_cache
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Path, Query, Response, status
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.db import get_db
from app.models import GistdaFeature, GistdaFetch, GistdaTile
from app.providers.base import ProviderError
from app.providers.gistda import PERIODS, GistdaApi, GistdaKeyError
from app.services import gistda

router = APIRouter(prefix="/gistda", tags=["gistda"], dependencies=[Depends(require_admin)])
THAILAND = (97.0, 5.0, 106.0, 21.0)


@lru_cache
def get_gistda_api() -> GistdaApi:
    return GistdaApi()


class FeaturesRequest(BaseModel):
    dataset: Literal["flood", "hotspots"]
    period_days: Literal[1, 3, 7, 30] = 1
    bbox: list[float] = Field(min_length=4, max_length=4, description="west,south,east,north (EPSG:4326)")
    boundary_wkt: str | None = Field(default=None, description="Optional EPSG:4326 (multi)polygon to clip to")

    @model_validator(mode="after")
    def check_bbox(self):
        west, south, east, north = self.bbox
        if not (west < east and south < north):
            raise ValueError("bbox must be west,south,east,north")
        if west < THAILAND[0] or south < THAILAND[1] or east > THAILAND[2] or north > THAILAND[3]:
            raise ValueError("bbox must lie within Thailand")
        return self


def _upstream_error(exc: Exception) -> HTTPException:
    if isinstance(exc, GistdaKeyError):
        return HTTPException(status.HTTP_502_BAD_GATEWAY, {"code": "gistda_key_rejected", "message": str(exc)})
    if isinstance(exc, gistda.MissingKey):
        return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, {"code": "gistda_key_missing", "message": str(exc)})
    return HTTPException(status.HTTP_502_BAD_GATEWAY, {"code": "gistda_unavailable", "message": str(exc)})


@router.post("/features")
def features(body: FeaturesRequest, x_gistda_api_key: str | None = Header(default=None),
             db: Session = Depends(get_db), api: GistdaApi = Depends(get_gistda_api)):
    try:
        return gistda.get_features(db, api, body.dataset, body.period_days, body.bbox,
                                   api_key=(x_gistda_api_key or "").strip() or None, boundary_wkt=body.boundary_wkt)
    except (gistda.MissingKey, ProviderError) as exc:
        raise _upstream_error(exc) from exc


@router.get("/tiles/{layer}/{z}/{x}/{y}")
def tile(layer: Literal["drought", "flood"], z: int = Path(ge=5, le=18), x: int = Path(ge=0), y: int = Path(ge=0),
         period_days: int = Query(default=7, description="1, 3, 7 or 30"), x_gistda_api_key: str | None = Header(default=None),
         db: Session = Depends(get_db), api: GistdaApi = Depends(get_gistda_api)):
    # a Literal[int] query parameter would reject the string "7", so the period is checked here
    if period_days not in PERIODS:
        raise HTTPException(422, "period_days must be 1, 3, 7 or 30")
    if x >= 2 ** z or y >= 2 ** z:
        raise HTTPException(422, "tile outside the grid")
    if layer == "drought":
        period_days = 7  # DRI+ is only published as a 7-day product
    try:
        content, content_type, cache = gistda.get_tile(db, api, layer, period_days, z, x, y,
                                                       api_key=(x_gistda_api_key or "").strip() or None)
    except (gistda.MissingKey, ProviderError) as exc:
        raise _upstream_error(exc) from exc
    if content is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT, headers={"X-Cache": cache})
    return Response(content=content, media_type=content_type or "image/png", headers={"X-Cache": cache})


@router.get("/status")
def cache_status(db: Session = Depends(get_db)):
    fetches = db.execute(
        select(GistdaFetch.dataset, GistdaFetch.period_days, func.count(GistdaFetch.id), func.max(GistdaFetch.fetched_at))
        .group_by(GistdaFetch.dataset, GistdaFetch.period_days)
    ).all()
    return {
        "periods": sorted(PERIODS),
        "queries": [{"dataset": d, "period_days": p, "cached_queries": n, "last_fetched_at": t} for d, p, n, t in fetches],
        "features": db.scalar(select(func.count(GistdaFeature.id))),
        "tiles": db.scalar(select(func.count(GistdaTile.id))),
    }
