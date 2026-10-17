#!/bin/sh
# Separate database for the pytest suite so tests never touch real data.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
  CREATE EXTENSION IF NOT EXISTS postgis;
  CREATE DATABASE weather_test;
SQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname weather_test -c "CREATE EXTENSION IF NOT EXISTS postgis;"
