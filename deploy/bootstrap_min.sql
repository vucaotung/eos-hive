-- Khởi tạo tối thiểu cho CSDL mới: 1 công ty, 1 phòng ban, 1 chủ sở hữu (quản trị hệ thống).
-- Giai đoạn 1 sẽ có màn hình thay cho tệp này. Chạy MỘT lần:
--   psql -d eos -v ON_ERROR_STOP=1 -v company_name='Công ty A' -v company_slug=cty-a -v dept_code=HC -v dept_name='Hành chính' \
--        -v owner_email=ten@gmail.com -v owner_name='Họ Tên' -f bootstrap_min.sql
-- In ra company_id (dùng cho setup_agents.sql) và owner_id (dùng để cấp mã MCP thử).
BEGIN;
WITH c AS (
  INSERT INTO core.companies (slug, name) VALUES (:'company_slug', :'company_name') RETURNING id
), d AS (
  INSERT INTO core.departments (company_id, code, name) SELECT id, :'dept_code', :'dept_name' FROM c RETURNING id, company_id
), u AS (
  INSERT INTO core.users (email, name, is_system_admin) VALUES (lower(:'owner_email'), :'owner_name', true) RETURNING id
), m AS (
  INSERT INTO core.memberships (user_id, company_id, department_id) SELECT u.id, d.company_id, d.id FROM u, d RETURNING user_id, company_id
)
SELECT 'company_id=' || company_id || ' owner_id=' || user_id FROM m;
COMMIT;
