"""Default Thai locations (province seats). Idempotent: upsert on `code`."""

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import WeatherLocation

DEFAULT_LOCATIONS = [
    dict(code="nakhon-sawan", name="Mueang Nakhon Sawan", name_th="เมืองนครสวรรค์", province="Nakhon Sawan",
         district="Mueang Nakhon Sawan", latitude=15.7047, longitude=100.1372),
    dict(code="bangkok", name="Bangkok", name_th="กรุงเทพมหานคร", province="Bangkok",
         district="Phra Nakhon", latitude=13.7563, longitude=100.5018),
    dict(code="chiang-mai", name="Mueang Chiang Mai", name_th="เมืองเชียงใหม่", province="Chiang Mai",
         district="Mueang Chiang Mai", latitude=18.7883, longitude=98.9853),
    dict(code="khon-kaen", name="Mueang Khon Kaen", name_th="เมืองขอนแก่น", province="Khon Kaen",
         district="Mueang Khon Kaen", latitude=16.4419, longitude=102.8360),
    dict(code="nakhon-ratchasima", name="Mueang Nakhon Ratchasima", name_th="เมืองนครราชสีมา",
         province="Nakhon Ratchasima", district="Mueang Nakhon Ratchasima", latitude=14.9799, longitude=102.0977),
    dict(code="phuket", name="Mueang Phuket", name_th="เมืองภูเก็ต", province="Phuket",
         district="Mueang Phuket", latitude=7.8804, longitude=98.3923),
    dict(code="hat-yai", name="Hat Yai", name_th="หาดใหญ่", province="Songkhla",
         district="Hat Yai", latitude=7.0086, longitude=100.4747),
]


def point(lon: float, lat: float):
    return func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)


def seed_locations(db: Session, timezone: str = "Asia/Bangkok") -> int:
    for loc in DEFAULT_LOCATIONS:
        values = {**loc, "timezone": timezone, "geom": point(loc["longitude"], loc["latitude"])}
        stmt = insert(WeatherLocation).values(**values)
        db.execute(stmt.on_conflict_do_nothing(index_elements=["code"]))
    db.commit()
    return len(DEFAULT_LOCATIONS)
