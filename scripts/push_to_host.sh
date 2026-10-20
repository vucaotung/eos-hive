#!/usr/bin/env bash
# Đưa bản đã commit (HEAD) lên một máy qua SSH, KHÔNG cần GitHub trên máy đích và không mang theo .git.
# Dùng: scripts/push_to_host.sh vps169 /opt/apps/enterprise-os      (chỉ chép db mcp web bridge deploy docs scripts VERSION)
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
HOST="${1:?alias SSH}"; DEST="${2:?thư mục đích}"
[ -z "$(git status --porcelain)" ] || { echo "Cây làm việc chưa sạch; chỉ triển khai bản đã commit." >&2; exit 2; }
git archive --format=tar HEAD db mcp web bridge deploy docs scripts VERSION | ssh -o BatchMode=yes "$HOST" "mkdir -p '$DEST' && tar -x -C '$DEST'"
echo "Đã chép $(git rev-parse --short HEAD) ($(cat VERSION)) sang $HOST:$DEST (không đụng .env, node_modules)"
