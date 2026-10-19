#!/usr/bin/env bash
# Replace the development databases with a dump (docker compose must be running).
# Uses the local dumps from dump.sh when present, otherwise the snapshot committed to git
# (databases/seed/2026-10-18, PostgreSQL split into parts to stay under GitHub's 100 MB limit).
# Pass a snapshot folder to choose one: databases/seed/restore.sh databases/seed/2026-10-18
# WARNING: drops all current data in smart_city_development (PostgreSQL and MongoDB).
set -euo pipefail
cd "$(dirname "$0")/../.."
SEED=databases/seed
SOURCE=${1:-}
if [[ -z "$SOURCE" ]]; then
  if [[ -f "$SEED/postgres_smart_city_development.dump" ]]; then SOURCE=$SEED; else SOURCE=$SEED/2026-10-18; fi
fi
PG_PARTS=("$SOURCE"/postgres_smart_city_development.dump*)
[[ -e "${PG_PARTS[0]}" && -f "$SOURCE/mongo_smart_city_development.archive.gz" ]] || { echo "No dump found in $SOURCE" >&2; exit 1; }

read -r -p "Restore from $SOURCE, replacing ALL development data in PostgreSQL and MongoDB? [y/N] " answer
[[ "$answer" == [yY] ]] || exit 1

docker compose stop web broadcast_worker >/dev/null 2>&1 || true
docker compose exec -T db psql -U smart_city -d postgres -qc "DROP DATABASE IF EXISTS smart_city_development WITH (FORCE)" \
  -c "CREATE DATABASE smart_city_development"
# A single .dump file, or its .part-aa, .part-ab, ... pieces joined in order.
cat "${PG_PARTS[@]}" | docker compose exec -T db pg_restore -U smart_city -d smart_city_development --no-owner --no-privileges
docker compose exec -T mongo mongorestore --quiet --drop --archive --gzip < "$SOURCE/mongo_smart_city_development.archive.gz"
docker compose start web broadcast_worker >/dev/null 2>&1 || true
echo "Restored. Rails secrets (API keys, tokens) only decrypt with the same secret_key_base / master key."
