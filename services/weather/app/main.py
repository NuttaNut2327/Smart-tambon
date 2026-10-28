from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.api import gistda, locations, weather
from app.config import get_settings
from app.db import get_db
from app.logging_setup import setup_logging
from app.models import WeatherIngestionLog

setup_logging(get_settings().log_level)

app = FastAPI(
    title="Smart Tambon Weather Data Feed API",
    version="1.0.0",
    description=(
        "Current conditions, append-only 7-day forecast archive, daily observations and forecast "
        "accuracy for Thai locations. Primary: Open-Meteo ECMWF IFS 0.25°; secondary: Open-Meteo GFS. "
        "Unavailable parameters are NULL (never 0) and listed in `unavailable_params`."
    ),
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"], allow_headers=["*"])
app.include_router(locations.router, prefix="/api/v1")
app.include_router(weather.router, prefix="/api/v1")
app.include_router(gistda.router, prefix="/api/v1")


@app.get("/health", tags=["meta"])
@app.get("/api/v1/health", tags=["meta"], include_in_schema=False)
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    last = db.execute(
        select(WeatherIngestionLog.job_type, func.max(WeatherIngestionLog.finished_at))
        .where(WeatherIngestionLog.status == "SUCCESS")
        .group_by(WeatherIngestionLog.job_type)
    ).all()
    return {"status": "ok", "database": "ok", "last_success": {job: ts for job, ts in last}}
