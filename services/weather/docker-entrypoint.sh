#!/bin/sh
set -e

case "$1" in
  api)
    alembic upgrade head
    python -m app.cli seed
    exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
    ;;
  scheduler)
    exec python -m app.scheduler
    ;;
  *)
    exec "$@"
    ;;
esac
