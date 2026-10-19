#!/bin/sh
# Thêm vào /opt/backup/backup.sh hiện có (đã mã hóa và Z2 kéo về lúc 04:00): dump CSDL Dẹo Work.
set -eu
cd "$(dirname "$0")"
docker compose exec -T db pg_dump -U postgres -d deo_work -Fc > "${1:-/var/backups/deo}/deo_work_$(date +%F).dump"
