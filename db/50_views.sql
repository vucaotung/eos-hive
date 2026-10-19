-- =====================================================================
-- Enterprise OS — 50 View dùng cho màn hình (security_invoker: RLS của bảng gốc vẫn áp dụng)
-- =====================================================================

-- Tình trạng công văn đến tính theo ngày hôm nay (giờ Việt Nam)
CREATE VIEW doc.incoming_v WITH (security_invoker = true) AS
SELECT i.*, s.code AS status_code,
       CASE s.code
         WHEN 'cancelled' THEN 'Đã hủy'
         WHEN 'done'      THEN 'Đã xong'
         WHEN 'done_late' THEN 'Xong trễ ' || (i.completed_on - i.deadline) || ' ngày'
         WHEN 'info'      THEN 'Để biết / lưu'
         WHEN 'overdue'   THEN 'Quá hạn ' || (d.today - i.deadline) || ' ngày'
         WHEN 'unassigned' THEN 'Chưa giao xử lý'
         WHEN 'due_today' THEN 'Hạn hôm nay'
         WHEN 'due_soon'  THEN 'Còn ' || (i.deadline - d.today) || ' ngày'
         ELSE 'Đang xử lý · hạn ' || to_char(i.deadline, 'DD/MM') END AS status_label,
       (i.handler_id IS NULL AND i.department_id IS NULL) AS unassigned
FROM doc.incoming i
CROSS JOIN LATERAL (SELECT (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS today) d
LEFT JOIN doc.settings st ON st.company_id = i.company_id
CROSS JOIN LATERAL (SELECT CASE
    WHEN i.cancelled THEN 'cancelled'
    WHEN i.completed_on IS NOT NULL AND (i.deadline IS NULL OR i.completed_on <= i.deadline) THEN 'done'
    WHEN i.completed_on IS NOT NULL THEN 'done_late'
    WHEN i.handling = 'info' THEN 'info'
    WHEN i.deadline < d.today THEN 'overdue'
    WHEN i.handler_id IS NULL AND i.department_id IS NULL THEN 'unassigned'
    WHEN i.deadline = d.today THEN 'due_today'
    WHEN i.deadline - d.today <= coalesce(st.soon_days, 3) THEN 'due_soon'
    ELSE 'in_progress' END AS code) s;

-- Số dư phép năm: phép + chuyển + điều chỉnh − đã dùng − đang chờ
CREATE VIEW hr.leave_balance_v WITH (security_invoker = true) AS
SELECT b.company_id, b.employee_id, b.year, b.entitled, b.carried_over, b.adjusted,
       coalesce(u.used, 0) AS used, coalesce(u.pending, 0) AS pending,
       b.entitled + b.carried_over + b.adjusted - coalesce(u.used, 0) - coalesce(u.pending, 0) AS remaining
FROM hr.leave_balances b
LEFT JOIN LATERAL (
  SELECT sum(r.days) FILTER (WHERE r.state = 'approved') AS used,
         sum(r.days) FILTER (WHERE r.state = 'pending')  AS pending
    FROM hr.requests r JOIN hr.request_types t ON t.id = r.type_id AND t.uses_balance
   WHERE r.employee_id = b.employee_id AND extract(year FROM r.start_at) = b.year) u ON true;

-- Hộp "Chờ tôi duyệt" gộp mọi phân hệ: bước hiện tại của mỗi yêu cầu đang chờ
CREATE VIEW core.approval_inbox_v WITH (security_invoker = true) AS
SELECT r.id, r.company_id, r.entity_type, r.entity_id, r.title, r.department_id, r.requested_by, r.requested_at,
       r.round, r.current_step, s.name AS step_name, s.approver_kind, s.approver_role, s.approver_user
FROM core.approval_requests r
JOIN core.approval_steps s ON s.flow_id = r.flow_id AND s.step_no = r.current_step
WHERE r.state = 'pending';

-- Tra cứu chung (thanh tìm kiếm trên cùng): một danh sách cho mọi phân hệ
CREATE VIEW core.search_v WITH (security_invoker = true) AS
          SELECT company_id, 'task'::text AS kind, id::text AS ref, title AS label, search_key FROM work.tasks
UNION ALL SELECT company_id, 'incoming_doc', id::text, sender_name || ': ' || summary, search_key FROM doc.incoming
UNION ALL SELECT company_id, 'outgoing_doc', id::text, coalesce(ref_number || ': ', '') || summary, search_key FROM doc.outgoing
UNION ALL SELECT company_id, 'record', id::text, title, search_key FROM doc.records
UNION ALL SELECT company_id, 'employee', id::text, code || ' · ' || full_name, search_key FROM hr.employees
UNION ALL SELECT company_id, 'customer', id::text, name, search_key FROM crm.customers
UNION ALL SELECT company_id, 'kb_page', id::text, title, search_key FROM kb.pages WHERE state = 'published';
