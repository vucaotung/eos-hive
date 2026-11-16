#!/usr/bin/env bash
# Lớp vỏ mỏng cho Linux: gọi CLI Python. Dùng: fetch_drive.sh <slug> <id thư mục Drive>
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${PYTHON:-python3}" -m pipeline fetch "$@"
