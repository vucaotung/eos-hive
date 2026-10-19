#!/bin/sh
# Dựng lại CSDL thử nghiệm cục bộ
P="psql -h ${PGHOST:-/tmp/pgtest} -p ${PGPORT:-5544} -U postgres -v ON_ERROR_STOP=1 -q"
D=$(dirname "$0")
$P -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='deo_work' and pid<>pg_backend_pid()" >/dev/null; $P -c "drop database if exists deo_work" -c "create database deo_work" 2>/dev/null
$P -d deo_work -f $D/01_schema.sql && $P -d deo_work -f $D/02_functions.sql && $P -d deo_work -v authenticator_pw=devpass -v auth_svc_pw=authpass -f $D/03_security.sql 2>/dev/null
