-- Hồ sơ AI agent theo công ty (docs/17): chức danh, mô tả, người phụ trách theo bảng phân vai. KHÔNG chạy tự động.
-- Dùng: psql -v company=<uuid-công-ty> -v owner_email=<email-người-phụ-trách> -f deploy/setup_agent_profiles.sql        (cần migration 0023)
-- Chạy lại không tạo trùng. Quy tắc cập nhật: mô tả luôn đặt theo bảng; chức danh và người phụ trách chỉ đặt khi đang TRỐNG (không ghi đè chỉnh tay trên giao diện);
-- nhận việc Kanban (company_agents.enabled): mai, nhan-su, phap-che luôn đặt false (mai chỉ dùng mã MCP riêng, không nhận thẻ Kanban).
-- Không tạo core.memberships cho agent (Mai đã có membership từ trước, cần cho công cụ MCP của người; script này không đụng tới). Không đổi max_level, can_delegate, skills.
\set ON_ERROR_STOP on
BEGIN;

-- 1. Mai: chỉ thêm khi chưa có (có thể đã tạo thẳng trên VPS). Không có skill, không chia việc, mã MCP riêng đọc + tạo việc mới.
INSERT INTO core.users (email, name, kind) VALUES ('mai@agent.enterpriseos.bond', 'Mai - Trợ lý AI', 'agent') ON CONFLICT DO NOTHING;
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, executor, token_scopes, description)
SELECT u.id, 'mai', 'Mai - Trợ lý AI', 'specialist', 'work', 'team_admin', '{}', 1, false, 'hermes', '{read,task_create}', 'x'
  FROM core.users u WHERE lower(u.email) = 'mai@agent.enterpriseos.bond' AND u.kind = 'agent'
ON CONFLICT (code) DO NOTHING;
INSERT INTO agent.company_agents (company_id, agent_id, enabled)
SELECT :'company'::uuid, g.id, false FROM agent.agents g WHERE g.code = 'mai' ON CONFLICT DO NOTHING;

-- 2. Bảng phân vai
CREATE TEMP TABLE _roles (code text PRIMARY KEY, title text NOT NULL, descr text NOT NULL, enabled_false boolean NOT NULL) ON COMMIT DROP;
INSERT INTO _roles VALUES
 ('mai', 'Trợ lý tiếp nhận', 'Tiếp nhận yêu cầu qua Zalo/Telegram, trả lời thông tin, ghi nhận thông tin bổ sung chờ chủ sở hữu duyệt; chỉ tạo việc mới cho người theo lệnh của người được ủy quyền.', true),
 ('dieu-phoi', 'Điều phối dự án', 'Chia việc dự án cho agent chuyên môn, theo dõi, tổng hợp; không tự làm việc chuyên môn.', false),
 ('van-thu', 'Văn thư', 'Công văn NĐ 30, biên mục hồ sơ; không cấp số, không ký, không gửi ra ngoài.', false),
 ('quan-tri-du-lieu', 'Quản trị dữ liệu', 'Kiểm chất lượng dữ liệu, nạp kho tri thức; chỉ nạp thông tin đã duyệt.', false),
 ('ho-so-runner', 'Xử lý hồ sơ (Z2)', 'Đọc Drive, chuyển Markdown, OCR trong thư mục dự án.', false),
 ('nhan-su', 'Nhân sự', 'Nháp chấm công, KPI; chưa có skill.', true),
 ('phap-che', 'Pháp chế', 'Rà soát pháp lý hồ sơ, không kết luận thay luật sư; chưa có profile.', true);

UPDATE agent.agents g SET description = r.descr FROM _roles r WHERE g.code = r.code AND g.description IS DISTINCT FROM r.descr;
UPDATE agent.company_agents ca SET title = r.title
  FROM _roles r JOIN agent.agents g ON g.code = r.code
 WHERE ca.company_id = :'company'::uuid AND ca.agent_id = g.id AND ca.title IS NULL;
UPDATE agent.company_agents ca SET enabled = false
  FROM _roles r JOIN agent.agents g ON g.code = r.code
 WHERE ca.company_id = :'company'::uuid AND ca.agent_id = g.id AND r.enabled_false AND ca.enabled;
-- người phụ trách: phải là thành viên người của công ty (trigger company_agents_owner_chk cũng kiểm)
UPDATE agent.company_agents ca SET owner_user_id = o.id
  FROM _roles r JOIN agent.agents g ON g.code = r.code,
       (SELECT u.id FROM core.users u JOIN core.memberships m ON m.user_id = u.id AND m.company_id = :'company'::uuid AND m.active
         WHERE lower(u.email) = lower(:'owner_email') AND u.kind = 'person' AND u.active) o
 WHERE ca.company_id = :'company'::uuid AND ca.agent_id = g.id AND ca.owner_user_id IS NULL;

SELECT g.code, ca.title, (SELECT name FROM core.users WHERE id = ca.owner_user_id) AS owner, ca.enabled FROM agent.company_agents ca JOIN agent.agents g ON g.id = ca.agent_id
 WHERE ca.company_id = :'company'::uuid ORDER BY g.code;
COMMIT;
