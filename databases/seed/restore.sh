#!/usr/bin/env bash
# Replace the development databases with the dumps in this folder (docker compose must be running).
# WARNING: drops all current data in smart_city_development (PostgreSQL and MongoDB).
set -euo pipefail
cd "$(dirname "$0")/../.."
SEED=databases/seed

read -r -p "This replaces ALL development data in PostgreSQL and MongoDB. Continue? [y/N] " answer
[[ "$answer" == [yY] ]] || exit 1

docker compose stop web broadcast_worker >/dev/null 2>&1 || true
docker compose exec -T db psql -U smart_city -d postgres -qc "DROP DATABASE IF EXISTS smart_city_development WITH (FORCE)" \
  -c "CREATE DATABASE smart_city_development"
docker compose exec -T db pg_restore -U smart_city -d smart_city_development --no-owner --no-privileges \
  < "$SEED/postgres_smart_city_development.dump"
docker compose exec -T mongo mongorestore --quiet --drop --archive --gzip < "$SEED/mongo_smart_city_development.archive.gz"
docker compose start web broadcast_worker >/dev/null 2>&1 || true
echo "Restored. Rails secrets (API keys, tokens) only decrypt with the same secret_key_base / master key."
