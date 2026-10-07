#!/bin/bash
# Creates one database and one owner role per BusLink service.
#
# The postgres image runs this once, on first start with an empty data volume.
# To re-run it: docker compose -f infra/docker-compose.yml down -v  (deletes all data)
#
# Each service owns its own database and never reads another service's tables.
# route-service also gets the PostGIS extension for road geometry.
set -euo pipefail

create_service_db() {
  local name="$1" password="$2" postgis="$3"

  echo "buslink-init: creating database '${name}' owned by role '${name}'"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
       -v role="$name" -v pw="$password" <<'SQL'
CREATE ROLE :"role" LOGIN PASSWORD :'pw';
CREATE DATABASE :"role" OWNER :"role";
SQL

  if [ "$postgis" = "postgis" ]; then
    echo "buslink-init: enabling PostGIS in '${name}'"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$name" \
         -c "CREATE EXTENSION IF NOT EXISTS postgis;"
  fi
}

create_service_db route     "${ROUTE_DB_PASSWORD:-route}"         postgis
create_service_db fare      "${FARE_DB_PASSWORD:-fare}"           plain
create_service_db wallet    "${WALLET_DB_PASSWORD:-wallet}"       plain
create_service_db analytics "${ANALYTICS_DB_PASSWORD:-analytics}" plain

echo "buslink-init: done"
