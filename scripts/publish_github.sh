#!/usr/bin/env bash
# Tạo repo GitHub RIÊNG TƯ và đẩy main + tag. Chạy trên máy đã `gh auth login`. Hỏi xác nhận trước khi tạo.
# Dùng: scripts/publish_github.sh [owner/tên]   (mặc định vucaotung/eos-hive)
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
REPO="${1:-vucaotung/eos-hive}"; VER="v$(cat VERSION)"
command -v gh >/dev/null || { echo "Cần cài gh (https://cli.github.com)" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh chưa đăng nhập. Chạy: unset GH_TOKEN; gh auth login" >&2; exit 2; }
scripts/check_secrets.sh
[ -z "$(git status --porcelain)" ] || { echo "Cây làm việc chưa sạch, hãy commit trước." >&2; exit 2; }
git rev-parse "$VER" >/dev/null 2>&1 || git tag -a "$VER" -m "Phiên bản $VER"
read -r -p "Tạo repo RIÊNG TƯ $REPO và đẩy main + $VER? [gõ yes] " A; [ "$A" = yes ] || { echo "Đã hủy."; exit 1; }
if gh repo view "$REPO" >/dev/null 2>&1; then echo "Repo đã tồn tại, chỉ đẩy."; git remote get-url origin >/dev/null 2>&1 || git remote add origin "git@github.com:$REPO.git"
else gh repo create "$REPO" --private --source=. --remote=origin --description "Tổ Ong (eos-hive): Enterprise OS có AI agent làm việc cùng người" ; fi
git push -u origin main --follow-tags
gh repo view "$REPO" --json visibility,url -q '.visibility+" "+.url'
