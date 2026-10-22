#!/usr/bin/env bash
# Ghép các tệp db/*.sql thành một tệp duy nhất (để nạp nhanh hoặc đưa vào Project). Dùng: scripts/build_schema.sh > eos-schema.sql
. "$(dirname "$0")/_common.sh"
for f in "${DB_FILES[@]}"; do echo "-- ===== $f.sql ====="; cat "$ROOT/db/$f.sql"; echo; done
