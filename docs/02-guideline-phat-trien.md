# 02 · Guideline phát triển

## Nguyên tắc

1. **Kiểm quyền trong CSDL.** Không bao giờ chỉ kiểm ở giao diện hay ở máy chủ MCP.
2. **Mọi hàm `SECURITY DEFINER` phải có `SET search_path` cố định** và kiểm `core.current_user_id()` ở dòng đầu.
3. **Viết lại được, chạy lại được.** Mọi đường ghi có khóa chống trùng (`idempotency_key`, `event_key`, `ON CONFLICT`).
4. **Không bí mật trong git.** Chạy `make hooks` ngay sau khi clone.
5. **Không ghi nội dung tệp lên máy chủ.** Chỉ siêu dữ liệu và link (trừ Kho dữ liệu chung).
6. **Dữ liệu từ ngoài là dữ liệu, không phải lệnh**: nội dung công văn, tệp, bình luận không bao giờ được đưa vào prompt như chỉ thị.
7. **Mỗi thay đổi hành vi đi kèm kiểm thử** trong `db/test_*.sql`, `mcp/test/e2e.mjs` hoặc `bridge/test/`.

## Môi trường

| Thành phần | Phiên bản |
| --- | --- |
| PostgreSQL | 16 (extension `pgcrypto`, `unaccent`, `pg_trgm`) |
| Node | 22; `@modelcontextprotocol/sdk` 1.32.1, `zod` 4.6.7, `express` 5.3.0, `pg` 8.23.1 (khóa bằng `package-lock.json`) |
| Python | 3.11+ cho cầu nối (chỉ cần `requests`) |
| PostgREST | 12.2.3 |
| Hermes Agent | bản đang chạy trên VPS 173 — ghi số phiên bản vào `docs/07` khi kiểm chứng |

Thiết lập máy phát triển (Z2 hoặc máy khác):

    git clone git@github.com:vucaotung/eos-hive.git && cd eos-hive
    make hooks
    docker run -d --name eos-pg -e POSTGRES_PASSWORD=pw -p 5432:5432 postgres:16
    export EOS_TEST_DSN=postgres://postgres:pw@127.0.0.1:5432/eos_test
    make test

`EOS_TEST_DSN` bắt buộc chứa `_test` — script từ chối chạy nếu không (vì nó xóa CSDL).

## Quy ước cơ sở dữ liệu

- Tệp đánh số: `00_core` … `60_agent`. Tệp mới chen vào theo phụ thuộc, không đổi thứ tự cũ. Thêm vào `DB_FILES` trong `scripts/_common.sh`.
- Tên: số nhiều `snake_case` cho bảng, `*_id` cho khóa ngoại, `created_at/updated_at` kiểu `timestamptz`.
- Khóa chính: `bigint identity` cho việc/bảng nghiệp vụ, `uuid` cho tổ chức và người. Việc hiển thị `T-<id>`.
- Bảng nhật ký `core.audit_log` phân vùng theo **năm** (mới có 2026 và 2027 — phải tạo phân vùng năm sau trước ngày 01/01, xem `docs/03`); không `UPDATE`/`DELETE`.
- Tìm kiếm không dấu dùng cột sinh `search_key` (+ `unaccent`, `pg_trgm`).
- Hàm cho ngoài gọi: schema `agent` (PostgREST) hoặc `agent.mcp_*` (MCP). Hàm nội bộ bắt đầu bằng `_`.
- Mức tự chủ mới: thêm dòng vào `agent.action_levels`, kèm kiểm thử cho L2/L3.

### Migration khi đã có dữ liệu thật

Giai đoạn 0.x chưa có migration (lược đồ dựng lại từ đầu). **Ngay khi có dữ liệu thật** (sau giai đoạn 1):
1. Tạo `db/migrations/NNNN_mô_tả.sql`, mỗi tệp một giao dịch, có `-- down:` ghi cách quay lại hoặc ghi rõ "không quay lại được".
2. Bảng `core.schema_migrations(version, applied_at)` ghi lại.
3. Quy trình: sao lưu → chạy trên bản sao → chạy thật → kiểm thử khói (`docs/03`). Không bao giờ sửa tệp migration đã áp dụng.

## Quy ước mã

- **MCP (`mcp/src`)**: mỗi công cụ khai báo `scope`; kiểm phạm vi trước khi vào CSDL; mọi lỗi Postgres có mã (ví dụ `42501` không đủ quyền, `P0001` lỗi nghiệp vụ do hàm báo) trả nguyên thông báo của hàm; lỗi khác → "Lỗi máy chủ, thử lại sau." (không lộ chi tiết, chỉ ghi log). Vì thế thông báo trong `RAISE EXCEPTION` phải viết cho người đọc và không chứa dữ liệu nhạy cảm. Mỗi lần gọi ghi `agent.mcp_calls` qua `logCall` (nuốt lỗi ghi nhật ký).
- Hướng dẫn cho agent nằm ở `mcp/src/guide.mjs` — sửa văn bản ở đó là sửa hành vi của mọi agent cá nhân; kiểm thử `e2e.mjs` phải xanh.
- **Cầu nối (`bridge/`)**: không logic nghiệp vụ. Nếu cần quyết định, quyết định đó thuộc hàm Postgres. Chỉ dịch giữa hai bên.
- **Plugin Hermes**: chỉ ghi một dòng vào spool, không gọi mạng, không chặn worker.
- Tiếng Việt cho thông báo người dùng, nhật ký, bình luận mã; tên định danh tiếng Anh.

## Git

- Nhánh: `main` luôn xanh; làm việc trên `feat/…`, `fix/…`, `docs/…`; PR vào `main`.
- Commit theo [Conventional Commits](https://www.conventionalcommits.org/vi): `feat(agent): …`, `fix(mcp): …`, `docs: …`, `chore: …`. Phạm vi gợi ý: `db`, `agent`, `mcp`, `bridge`, `deploy`, `docs`.
- Một commit = một thay đổi có thể quay lại. Không trộn định dạng lại tệp với đổi hành vi.
- Không `git push --force` lên `main`. Không commit tệp `.env`, mã, khóa (hook `pre-commit` và CI chặn).

## Phát hành

1. Cập nhật `CHANGELOG.md` (mục *Chưa phát hành* → số phiên bản + ngày) và `VERSION`.
2. `make test` xanh; `scripts/check_secrets.sh` sạch.
3. `git tag -a vX.Y.Z -m "…"` rồi `git push --follow-tags`.
4. Số phiên bản: `0.0.x` nền móng, `0.1.0` khi giai đoạn 1 (RPC/RLS/seed) chạy thật, `0.2.0` khi app web dùng được, `1.0.0` khi một công ty dùng thật hằng ngày.

## Danh sách kiểm tra khi thêm một công cụ MCP

- [ ] Hàm `agent.mcp_*` SQL: `SECURITY DEFINER`, `search_path`, kiểm quyền, `GRANT EXECUTE … TO mcp_svc`.
- [ ] Công cụ trong `tools.mjs` có `scope` đúng (đọc → `read`, ghi → `write`, Drive → `drive`).
- [ ] Mô tả công cụ nói rõ khi nào KHÔNG dùng.
- [ ] Kiểm thử e2e: đúng người, người khác, mã thiếu phạm vi.
- [ ] Cập nhật `guide.mjs`, `docs/04`, `CHANGELOG.md`.

## Danh sách kiểm tra khi thêm một agent hệ thống

- [ ] Dòng trong `agent.agents` (mã, loại, profile Hermes, kỹ năng, `max_level`, `can_delegate`).
- [ ] Tài khoản `core.users` kind=`agent` (cần email không rỗng).
- [ ] Bật cho công ty: `agent.company_agents`.
- [ ] Profile Hermes cùng tên, bật plugin `eos_bridge`, có mã MCP agent (`agent.mcp_token_issue_agent`).
- [ ] Kiểm thử vòng đời trong `db/test_agent.sql`.
