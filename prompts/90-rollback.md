# 90 · Quay lại (rollback)

Nguyên tắc: **Tổ Ong là bổ sung độc lập**; quay lại = gỡ phần đã thêm, không đụng thứ có sẵn. Mọi lệnh dưới đây hỏi người dùng trước khi chạy. Dữ liệu trong CSDL `eos` chỉ xóa khi người dùng nói rõ "xóa dữ liệu".

## VPS 173

| Đã làm | Quay lại |
| --- | --- |
| Cầu nối | `systemctl --user disable --now eos-kanban-bridge`; `rm ~/.config/systemd/user/eos-kanban-bridge.service`; giữ `~/.hermes/eos_bridge` (chứa `cards.json` để đối soát) hoặc chuyển vào `_to_delete/` |
| Plugin `eos_bridge` | Tắt plugin ở các profile `eos-*`; chuyển thư mục plugin sang `_to_delete/` |
| 4 profile `eos-*` | Chỉ khi người dùng đồng ý: `hermes profile` xóa/lưu trữ từng profile. Không đụng profile khác |
| Thẻ Kanban | `hermes kanban archive` các thẻ trên board `eos-*` |
| Mã `.env` | Xóa dòng `EOS_MCP_TOKEN` trong `.env` các profile `eos-*`; thu hồi mã tương ứng ở CSDL |

## VPS 169

| Đã làm | Quay lại |
| --- | --- |
| Caddy | Khôi phục `Caddyfile.bak.*` gần nhất: `cp -a … /etc/caddy/Caddyfile && caddy validate --config … && systemctl reload caddy` |
| MCP | `systemctl disable --now eos-mcp`; xóa unit; `.env` giữ lại hoặc `_to_delete/` |
| PostgREST | `systemctl disable --now postgrest-eos`; xóa unit; `/etc/eos/postgrest.conf` giữ lại |
| CSDL `eos` | **Dump trước**: `docker exec eos-postgres pg_dump -U postgres -Fc eos > /var/backups/deo/eos_final.dump`. Chỉ khi người dùng đồng ý xóa: `docker compose -p eos-hive -f docker-compose.postgres.yml down` (giữ volume `eos_pgdata`); xóa volume chỉ khi chắc chắn |
| Sao lưu | Khôi phục `backup.sh.bak.*` |
| Người dùng `eos`, `/opt/apps/enterprise-os`, `/etc/eos` | Chuyển vào `_to_delete/`, báo người dùng tự xóa |

Ever Teams, WeKnora, evidence-db không bị thay đổi nên không cần quay lại.

## Z2

| Đã làm | Quay lại |
| --- | --- |
| Container `eos-pg` | `docker rm -f eos-pg` (dữ liệu thử, vô hại) |
| `~/.config/eos-hive` | Xóa tệp `pg.env`, `smoke.env` |
| Repo | Giữ nguyên; GitHub: đặt repo về private/lưu trữ, **không** xóa nếu chưa hỏi |

## Sự cố giữa chừng

- **Nạp lược đồ dở dang**: `DROP DATABASE eos` rồi dựng lại từ `00` (chỉ khi CSDL chưa có dữ liệu thật).
- **Caddy hỏng**: khôi phục `.bak`, `caddy validate`, reload. Kiểm các site khác (`teams.`, `teams-api.`) vẫn lên.
- **Hermes gateway không lên sau khi bật plugin**: tắt plugin, `systemctl --user restart hermes-gateway`, kiểm Telegram/Zalo của người dùng lên lại **trước tiên** — đó là hệ thống đang dùng thật.
- **Nghi lộ bí mật**: `docs/05` mục G.
