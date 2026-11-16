#!/usr/bin/env bash
# Lớp vỏ mỏng cho Linux: gọi CLI Python. Dùng: run_project.sh <slug>
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${PYTHON:-python3}" -m pipeline run "$@"
