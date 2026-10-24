-- 0013 · Agent chặn hỏi → người trả lời → agent chạy lại rồi chặn lần nữa: thẻ chuyển sang 'running' ngay khi câu trả lời được gửi cho Hermes,
-- để lần chặn kế tiếp không bị agent.ingest_event bỏ qua là 'no_change' (việc đứng yên, câu hỏi mới không tới người). Kèm sửa cầu nối (khóa sự kiện theo epoch).
-- Nguồn chính: db/60_agent.sql. Idempotent. down: khôi phục agent.comments_relay_trg từ migration 0008.
BEGIN;
CREATE OR REPLACE FUNCTION agent.comments_relay_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE t work.tasks; c agent.cards; s agent.company_settings;
BEGIN
  IF NEW.actor LIKE 'agent:%' OR NEW.kind NOT IN ('answer','reject') THEN RETURN NEW; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = NEW.task_id;
  IF t.agent_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO c FROM agent.cards WHERE task_id = t.id ORDER BY attempt DESC, id DESC LIMIT 1;
  IF NEW.kind = 'answer' AND c.status = 'blocked' THEN
    IF c.card_id LIKE 'runner-%' THEN
      UPDATE agent.cards SET status = 'ready', last_event_at = now() WHERE id = c.id;   -- runner nhận lại thẻ, đọc câu trả lời ở phần phản hồi (mcp_runner_claim)
    ELSE
      INSERT INTO agent.outbox (company_id, kind, task_id, card_ref, payload)
      VALUES (t.company_id, 'answer', t.id, c.id, jsonb_build_object('board', c.board, 'card_id', c.card_id, 'body', NEW.body, 'by', NEW.actor));
      -- agent sẽ chạy lại: thẻ coi là đang chạy, để lần chặn kế tiếp (câu hỏi mới) không bị bỏ qua là "không đổi" (việc đứng yên)
      UPDATE agent.cards SET status = 'running', last_event_at = now() WHERE id = c.id;
    END IF;
    UPDATE work.tasks SET status = 'in_progress', waiting_on_human = false, updated_at = now() WHERE id = t.id;
  ELSIF NEW.kind = 'reject' AND t.status = 'in_review' THEN
    SELECT * INTO s FROM agent.company_settings WHERE company_id = t.company_id;
    UPDATE agent.reports SET verdict = 'rework' WHERE task_id = t.id AND verdict = 'pending';
    IF t.attempts + 1 > s.max_rework THEN
      -- quá số lần làm lại: trả việc cho người, agent dừng
      UPDATE work.tasks SET status = 'todo', agent_id = NULL, updated_at = now() WHERE id = t.id;
      PERFORM agent._notify(t.company_id, t.assignee_id, 'agent_gave_back', 'Agent đã làm lại ' || s.max_rework || ' lần, việc chuyển về bạn', t.id);
    ELSE
      UPDATE work.tasks SET attempts = attempts + 1, status = 'todo', result = NULL, updated_at = now() WHERE id = t.id;
      -- trigger tasks_dispatch tạo thẻ rework; ghi lý do vào payload của thẻ mới
      UPDATE agent.outbox SET payload = payload || jsonb_build_object('rework_reason', NEW.body, 'parent_card_id', c.card_id)
       WHERE id = (SELECT max(id) FROM agent.outbox WHERE task_id = t.id AND kind = 'dispatch');
    END IF;
  END IF;
  RETURN NEW;
END $$;
COMMIT;
