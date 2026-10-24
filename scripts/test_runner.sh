#!/usr/bin/env bash
# Kiểm thử runner Z2 (docs/12) và script báo cáo (ops/eos_report.py, docs/13) bằng MCP giả; không cần Postgres/Drive/rclone. Chạy: make test-runner
. "$(dirname "$0")/_common.sh"
cd "$ROOT"
for t in runner/test/test_runner.py ops/test/test_report.py; do
  OUT=$(python3 -I "$t" 2>&1) || { echo "$t: THẤT BẠI" >&2; echo "$OUT" | tail -15 >&2; exit 1; }
  echo "$t: $(echo "$OUT" | tail -3 | tr '\n' ' ')"
done
