#!/usr/bin/env bash
# Dump the development PostgreSQL/PostGIS and MongoDB databases into this folder (docker compose must be running).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=databases/seed

docker compose exec -T db pg_dump -U smart_city -d smart_city_development -Fc -Z 9 --no-owner --no-privileges \
  > "$OUT/postgres_smart_city_development.dump"
docker compose exec -T mongo mongodump --quiet --db smart_city_development --archive --gzip \
  > "$OUT/mongo_smart_city_development.archive.gz"
ls -lh "$OUT"
