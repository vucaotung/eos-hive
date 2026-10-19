#!/usr/bin/env bash
# Chặn bí mật lọt vào git. Chạy trước mỗi commit (hook pre-commit gọi script này). Thoát 1 nếu thấy.
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
PAT='(-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}|eos_[0-9a-f]{48}|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}|GOCSPX-[A-Za-z0-9_-]{10,}|1//0[A-Za-z0-9_-]{30,})'
FILES=$(git ls-files -co --exclude-standard 2>/dev/null || find . -type f -not -path './.git/*' -not -path '*/node_modules/*')
HIT=$(echo "$FILES" | grep -v -E '(package-lock\.json|\.png$|\.zip$)' | xargs grep -I -n -E "$PAT" 2>/dev/null | grep -v 'test-only' || true)
if [ -n "$HIT" ]; then echo "PHÁT HIỆN BÍ MẬT:"; echo "$HIT" | cut -c1-140; exit 1; fi
BAD=$(echo "$FILES" | grep -E '(^|/)\.env$|\.env\.(local|prod)|id_(rsa|ed25519)$|\.pem$|\.key$|refresh_token|tokens\.env' || true)
if [ -n "$BAD" ]; then echo "TỆP KHÔNG ĐƯỢC ĐƯA VÀO GIT:"; echo "$BAD"; exit 1; fi
echo "check_secrets: sạch"
