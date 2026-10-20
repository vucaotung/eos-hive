#!/usr/bin/env bash
# Cài một skill Hermes từ repo vào MỘT profile trên máy Hermes (chép thư mục, rồi Hermes tự kiểm tra).
# Dùng: scripts/install_skill.sh vps173 eos-van-thu nd30-van-thu [nhóm=van-thu]
# Chỉ chép bản đã commit; chép đè bản cũ của CHÍNH skill này (sao lưu thành .bak.<giờ>). Không đụng profile khác.
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
HOST="${1:?alias máy Hermes}"; PROFILE="${2:?profile (eos-…)}"; SKILL="${3:?tên skill}"; GROUP="${4:-van-thu}"
[[ "$PROFILE" =~ ^eos-[a-z-]{2,40}$ ]] || { echo "Chỉ cài vào profile eos-*" >&2; exit 2; }
[[ "$SKILL" =~ ^[a-z0-9-]{2,60}$ ]] || { echo "Tên skill không hợp lệ" >&2; exit 2; }
SRC="deploy/hermes-skills/$SKILL"; [ -f "$SRC/SKILL.md" ] || { echo "Không thấy $SRC/SKILL.md" >&2; exit 2; }
[ -z "$(git status --porcelain -- "$SRC")" ] || { echo "$SRC chưa commit; chỉ cài bản đã commit." >&2; exit 2; }
DEST="~/.hermes/profiles/$PROFILE/skills/$GROUP/$SKILL"
git archive --format=tar HEAD "$SRC" | tar -x -O --wildcards "$SRC/SKILL.md" | head -5 | grep -q "^name: $SKILL$" || { echo "SKILL.md không khai báo name: $SKILL" >&2; exit 2; }
git archive --format=tar HEAD "$SRC" | ssh -o BatchMode=yes "$HOST" "set -e; T=\$(mktemp -d); tar -x -C \"\$T\"; D=$DEST
  test -d \$(dirname \"\$D\") || mkdir -p \$(dirname \"\$D\")
  [ -e \"\$D\" ] && mv \"\$D\" \"\$D.bak.\$(date +%F-%H%M)\"
  cp -a \"\$T/$SRC\" \"\$D\"; rm -rf \"\$T\"; ls \"\$D\"; ls \"\$D/references\""
echo "Đã cài $SKILL vào $HOST:$DEST ($(git rev-parse --short HEAD))"
