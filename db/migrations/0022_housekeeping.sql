-- 0022 · agent.housekeeping_prune: dọn dòng cũ của bảng tạm lớp MCP. Không tự đặt lịch (docs/16 §6).
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP FUNCTION agent.housekeeping_prune(int).
BEGIN;
-- ---------- Dọn bảng tạm của lớp MCP (chạy theo lịch, xem docs/16) ----------
-- Xóa dòng cũ hơn p_days ngày (mặc định 1) ở: agent.task_create_keys (khóa chống trùng chỉ cần 15 phút), agent.drive_uploads (trạng thái done),
-- agent.kb_ingest_claims (giữ chỗ 'claiming' bị bỏ quên). KHÔNG đụng: drive_uploads failed/orphan (để người xem), kb_ingest_claims done (ghi nhận đã nạp), mcp_calls (nhật ký kiểm toán).
-- Bảng đếm tốc độ của máy chủ MCP nằm trong bộ nhớ tiến trình Node (tự dọn mỗi phút), không có bảng CSDL. Chỉ quản trị hệ thống.
CREATE OR REPLACE FUNCTION agent.housekeeping_prune(p_days int DEFAULT 1) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE a int; b int; c int; cutoff timestamptz;
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống chạy dọn' USING ERRCODE = '42501';
  END IF;
  IF p_days IS NULL OR p_days < 1 THEN RAISE EXCEPTION 'p_days tối thiểu 1'; END IF;
  cutoff := now() - make_interval(days => p_days);
  DELETE FROM agent.task_create_keys WHERE created_at < cutoff;
  GET DIAGNOSTICS a = ROW_COUNT;
  DELETE FROM agent.drive_uploads WHERE state = 'done' AND created_at < cutoff;
  GET DIAGNOSTICS b = ROW_COUNT;
  DELETE FROM agent.kb_ingest_claims WHERE state = 'claiming' AND claimed_at < cutoff;
  GET DIAGNOSTICS c = ROW_COUNT;
  RETURN jsonb_build_object('task_create_keys', a, 'drive_uploads_done', b, 'kb_claims_stale', c, 'older_than_days', p_days);
END $$;

COMMIT;
