#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE db_fleet_tracking;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "db_fleet_orders" <<-EOSQL
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS orders;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    -- PostGIS opcional aqui se precisar calcular frete estático
    CREATE EXTENSION IF NOT EXISTS postgis; 
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "db_fleet_tracking" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS postgis;
EOSQL