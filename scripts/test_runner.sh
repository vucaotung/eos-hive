#!/usr/bin/env bash
# Kiểm thử runner Z2 bằng MCP giả và lệnh ngoài giả (không cần Postgres, Drive, rclone). Chạy: make test-runner
. "$(dirname "$0")/_common.sh"
cd "$ROOT"
OUT=$(python3 -I runner/test/test_runner.py 2>&1) || { echo "runner: THẤT BẠI" >&2; echo "$OUT" | tail -15 >&2; exit 1; }
echo "$OUT" | tail -3 | tr '\n' ' '; echo
