# Weather Data Feed API & 7-Day Forecast Database

A standalone FastAPI service that sits next to the Smart Tambon Rails app. It ingests real weather data for Thai locations, keeps every forecast run so the forecasts can be scored later, and serves it all over a REST API. The Rails dashboard reads from this API: the weather panel on the overview page, and later the resource rules that use rainfall and wind metrics.

* **Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Pydantic v2, Alembic, APScheduler 3, HTTPX, PostgreSQL 16 + PostGIS 3.4
* **Data:** Open-Meteo, using ECMWF IFS 0.25° as the primary provider and NCEP GFS as the secondary. ERA5 and the Open-Meteo archive supply observations.
* **Rule:** the service never makes up a value. If a model has no value for a parameter, the service stores NULL (never 0) and lists that parameter in `unavailable_params`.

## Quick start

```bash
cd services/weather
cp .env.example .env          # set POSTGRES_PASSWORD and WEATHER_ADMIN_API_KEY
docker compose up -d --build
```

That one command:

1. starts `postgres` (PostGIS; host port **5442**, bound to 127.0.0.1). It also creates `weather_test` for the test suite.
2. starts `weather-api`, which runs `alembic upgrade head`, seeds the default locations and serves on **http://localhost:8010**.
3. starts `weather-scheduler` once the API is healthy. It runs an initial sync (forecast → current → observations) against Open-Meteo and then the recurring jobs.

After about 10 seconds you get real data:

```bash
curl "http://localhost:8010/api/v1/weather/forecast/daily?code=nakhon-sawan"
```

* API docs (OpenAPI): http://localhost:8010/docs. Health check: http://localhost:8010/health
* The host ports are chosen so they don't clash with the Rails stack, which uses 3000, 5432, 1883, 9000-9001 and 9883.

## Architecture

```
app/
  providers/        WeatherProvider interface + Open-Meteo ECMWF/GFS, archive (ERA5), stubs
  services/
    ingestion.py    idempotent persistence (append-only forecasts, revisable observations)
    jobs.py         job entry points, each under a Postgres advisory lock
    accuracy.py     MAE/RMSE/MBE, POD/FAR/CSI, Brier score
    locks.py        pg_try_advisory_lock helper
  api/              /api/v1 routers (weather, locations)
  scheduler.py      the ONLY process that registers recurring jobs
  seed.py, cli.py   default locations, manual sync/backfill CLI
alembic/            migrations
tests/              pytest (mocked providers) + opt-in live test
```

### Providers

| name | model | status | notes |
|---|---|---|---|
| `open_meteo_ecmwf` | `ecmwf_ifs025` | **primary** | ECMWF IFS 0.25° open data. It has **no `visibility` or `uv_index`**: those are stored as NULL and flagged in `unavailable_params` |
| `open_meteo_gfs` | `gfs_global` | secondary | NCEP GFS. Used only when the primary fails, and every row it produces is marked `is_fallback=true` with `fallback_reason` |
| `open_meteo_archive` | `era5` / `best_match` | observations | ERA5 reanalysis (about 5 days behind) is **FINAL**. More recent days use `best_match` (ECMWF IFS analysis), which is **PROVISIONAL** until ERA5 arrives |
| `nasa_gpm_imerg` | – | not implemented | stub (needs Earthdata credentials + HDF5 ingestion) |
| `jma_himawari` | – | not implemented | stub (needs a satellite product feed) |
| `tmd` | – | not implemented | stub (needs a TMD API key + station matching) |

Model identifiers and per-model parameter availability were checked against https://open-meteo.com/en/docs, https://open-meteo.com/en/docs/ecmwf-api and live responses on 2026-10-16. Each request passes the model explicitly (never `best_match`), so Open-Meteo does not quietly blend models or swap one in. Requests use `timeformat=unixtime`, so timestamps are parsed as UTC and daily dates come from the location's UTC offset.

**Retry and fallback:** each request is retried up to 4 times with exponential backoff (1 s, 2 s, 4 s + jitter) on network errors, 408/425/429 and 5xx. Other 4xx responses fail immediately. If the primary still fails, the secondary is tried. If both fail, the job records a `FAILED` log entry for that location and moves on to the other locations.

**Run ids:** a run id is `<model>@<init time>`, for example `ecmwf_ifs025@20261016T0600Z`, taken from Open-Meteo's model metadata (`/data/<model>/static/meta.json`). If the metadata can't be fetched, the id falls back to a 6-hour fetch bucket (`run_id_source = fetch_time_bucket`).

### Database tables

| table | purpose / key constraint |
|---|---|
| `weather_locations` | `code` unique, `geom` POINT(4326) with a GiST index |
| `weather_current` | model-derived current conditions. Unique on (location, provider, model, observed_at) |
| `weather_daily_forecast` | **append-only** archive of every run. Unique on (provider, model, run_id, location, forecast_date). Also stores `forecast_lead_days`, `issue_date` and `run_init_time` |
| `weather_daily_observation` | one row per (location, date, source_type, source_name). `source_type` is one of GROUND_STATION, SATELLITE_ESTIMATE, REANALYSIS, MODEL_DERIVED. `data_quality` is PROVISIONAL, FINAL or SUSPECT. Has `is_final` and `revision` |
| `weather_daily_observation_revisions` | the earlier values of each observation whenever it is revised |
| `weather_hourly` | `data_kind` is FORECAST (per run) or OBSERVED (`run_id='observed'`). Unique on (location, kind, provider, model, run_id, valid_time) |
| `weather_ingestion_logs` | one row per job and location: status, attempts, inserted/skipped counts, fallback, errors |

* All timestamps are stored in UTC (`timestamptz`).
* `forecast_date` and `observation_date` are local calendar dates in the location's timezone, which is also the timezone Open-Meteo aggregates daily values in.
* Lead day 0 is the issue date (the run's init time, in local time). The service fetches 8 days (today + 7), so lead days 1–7 can all be scored.

### Scheduler (Asia/Bangkok)

| job | trigger | what it does |
|---|---|---|
| `current` | every 30 min | current conditions |
| `forecast` | 00:15, 06:15, 12:15, 18:15 | 8-day daily + hourly forecast, append-only |
| `observation` | 02:00 | re-fetches the last 10 days plus any day that is still provisional. Values are revised until ERA5 is final. If anything is still provisional, it schedules one retry 3 h later |
| backfill | manual only | historical observations. **Never writes to the forecast archive** |

* Only `weather-scheduler` registers jobs; the API process never does.
* Every job, including `POST /weather/sync`, runs under `pg_try_advisory_lock(<job type>)`. A second instance or a manual sync that overlaps a running job is logged as `SKIPPED` and does not run.
* Logs are JSON, one object per line.

## REST API (`/api/v1`)

You can identify a location in any weather endpoint with `location_id`, `code`, or `lat`+`lon` (the nearest active location is used).

| method | path | auth | description |
|---|---|---|---|
| GET | `/health` | – | DB check + last successful run per job |
| GET | `/providers` | – | providers + implementation status |
| GET | `/weather/current` | – | latest current conditions |
| GET | `/weather/forecast/daily` | – | `days` (default 7) from the latest run, or from a given `run_id`, starting at local today |
| GET | `/weather/forecast/runs` | – | archived runs for a location |
| GET | `/weather/history/daily` | – | observations `start`..`end` (default: last 30 days). Filters: `source_type`, `final_only` |
| GET | `/weather/hourly` | – | `kind=forecast` (next 48 h, latest run) or `kind=observed`. A naive `start`/`end` is read as local time |
| GET | `/weather/accuracy` | – | verification per lead day. Params: `group_by` (any of location, province, provider, model, month, season), `lead_days`, `rain_threshold_mm`, `final_only` |
| GET | `/locations` · `/locations/search?q=` · `/locations/nearest?lat=&lon=` · `/locations/{id}` | – | list, search (Thai/English), lookup by GPS |
| POST / PATCH / DELETE | `/locations`, `/locations/{id}` | admin | CRUD |
| POST | `/weather/sync` | admin | `{"job": "current\|forecast\|observation\|backfill", "location_ids": [..], "start": "YYYY-MM-DD", "end": "YYYY-MM-DD"}` |
| GET | `/weather/ingestion-logs` | admin | recent ingestion logs |

For admin endpoints, send `X-API-Key: $WEATHER_ADMIN_API_KEY` (or `Authorization: Bearer …`). If the key is not set, admin endpoints return 503.

### Examples

```bash
# 7-day forecast (trimmed real response, 2026-10-16)
curl "localhost:8010/api/v1/weather/forecast/daily?code=nakhon-sawan"
```
```json
{
  "location": {"id": 1, "code": "nakhon-sawan", "name_th": "เมืองนครสวรรค์", "latitude": 15.7047, "longitude": 100.1372, "timezone": "Asia/Bangkok"},
  "run": {"run_id": "ecmwf_ifs025@20261016T0600Z", "provider": "open_meteo_ecmwf", "model": "ecmwf_ifs025",
          "run_init_time": "2026-10-16T06:00:00Z", "run_id_source": "model_metadata", "is_fallback": false,
          "unavailable_params": ["uv_index_max"]},
  "days": [
    {"forecast_date": "2026-10-16", "forecast_lead_days": 0, "weather_code": 80,
     "temperature_max_c": 33.6, "temperature_min_c": 25.3, "precipitation_sum_mm": 9.1,
     "precipitation_probability_max_pct": 67.0, "wind_speed_max_kmh": 7.7, "wind_gusts_max_kmh": 31.3,
     "uv_index_max": null, "sunrise": "2026-10-15T23:11:13Z", "sunset": "2026-10-16T10:57:54Z", "...": "..."},
    "... 6 more days ..."
  ]
}
```

```bash
# Current conditions at the location nearest to a GPS point
curl "localhost:8010/api/v1/weather/current?lat=15.70&lon=100.13"
# -> {"location": {...}, "current": {"observed_at": "2026-10-16T16:30:00Z", "temperature_c": 25.9,
#      "relative_humidity_pct": 93.0, "visibility_m": null, "uv_index": null,
#      "unavailable_params": ["visibility", "uv_index"], ...}, "note": "Model-derived current conditions ..."}

# Add a location, then pull its forecast right away
curl -X POST localhost:8010/api/v1/locations -H "X-API-Key: $KEY" -H 'content-type: application/json' \
  -d '{"code":"uthai-thani","name":"Mueang Uthai Thani","province":"Uthai Thani","latitude":15.3835,"longitude":100.0246}'
curl -X POST localhost:8010/api/v1/weather/sync -H "X-API-Key: $KEY" -H 'content-type: application/json' \
  -d '{"job":"forecast","location_ids":[8]}'
# -> {"job_type":"forecast","status":"SUCCESS","results":[{"location_id":8,"run_id":"ecmwf_ifs025@...","inserted":200,...}]}

# Backfill one year of observations (forecast archive untouched)
docker compose exec weather-api python -m app.cli backfill --start 2025-10-01 --end 2026-09-30

# Accuracy per lead day, by province and season
curl "localhost:8010/api/v1/weather/accuracy?start=2026-10-01&end=2026-10-31&group_by=province,season"
# -> {"pairs_total": ..., "results": [{"group": {"province": "Nakhon Sawan", "season": "rainy"}, "lead_days": 1,
#      "temperature_max": {"n": 31, "mae": 1.2, "rmse": 1.5, "mbe": -0.4}, "rainfall": {...},
#      "rain_occurrence": {"hits": 12, "misses": 3, "false_alarms": 5, "pod": 0.8, "far": 0.294, "csi": 0.6},
#      "rain_probability": {"n": 31, "brier_score": 0.18}}, ...]}
```

**How accuracy is scored:**

* For each location, model, issue date and target date, only the **latest run issued that day** counts, so the 4 runs a day are not counted 4 times.
* Forecasts are matched against observations of the same local date. Pass `final_only=true` to score only against FINAL (ERA5) days.
* A metric with no events comes back as `null`, not 0.
* Seasons follow the TMD seasons, rounded to whole months: winter Nov–Feb, summer Mar–May, rainy Jun–Oct.
* Scores accumulate over time. Forecasts can't be recreated after the fact, so there is no forecast backfill, and scores only exist from the day the service starts archiving runs.

## Tests

```bash
# Mocked providers, dedicated weather_test DB: 44 tests
docker compose run --rm weather-api pytest
# Opt-in live test against the real Open-Meteo API
docker compose run --rm -e WEATHER_LIVE_TESTS=1 weather-api pytest -m live
```

Coverage by file:

| file | what it covers |
|---|---|
| `test_api.py` | API shape, auth, OpenAPI routes |
| `test_locations.py` | CRUD, validation, search, GPS lookup |
| `test_ingestion.py` | forecast storage, historical preservation, duplicates, missing params, fallback, revision history |
| `test_open_meteo.py` | timezone/unixtime parsing, unavailable-param detection, retry/backoff, archive finality |
| `test_scheduler.py` | job registration in Asia/Bangkok, advisory locks, observation retry, local-time hourly queries |
| `test_accuracy.py` | MAE/RMSE/MBE, POD/FAR/CSI, Brier, grouping by lead day |

## Rails integration

* The dashboard overview page (`app/views/dashboard/_weather_panel.html.erb`, `app/javascript/weather_panel.js`) calls Rails `GET /api/weather`.
* That endpoint (`WeatherPanelService` + `WeatherFeedClient`) calls this service at `WEATHER_API_URL`, which defaults to `http://host.docker.internal:8010`.
* If the Rails app also has `WEATHER_ADMIN_API_KEY`, a user's own subdistrict is registered here automatically the first time they open the dashboard, provided no weather location exists within 10 km. Without the key, the panel shows the nearest seeded location and says how far away it is.

## Configuration (`.env`)

| variable | default | |
|---|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | weather / weather / weather | own database and volume (`weather_pgdata`) |
| `WEATHER_DB_HOST_PORT` | 5442 | |
| `WEATHER_API_HOST_PORT` | 8010 | |
| `WEATHER_ADMIN_API_KEY` | – | required for admin endpoints |
| `WEATHER_PRIMARY_PROVIDER` / `WEATHER_SECONDARY_PROVIDER` | open_meteo_ecmwf / open_meteo_gfs | |
| `WEATHER_FORECAST_DAYS` | 8 | today + 7 |
| `WEATHER_INITIAL_SYNC` | true | scheduler syncs once at start-up |
| `LOG_LEVEL` | INFO | |

**Note:** the `postgis/postgis` image is amd64-only, so on Apple Silicon it runs under emulation.
