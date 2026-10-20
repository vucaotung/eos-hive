-- 0001 · Hủy việc phải dừng thẻ Kanban (phát agent.outbox kind='cancel'). Phát hiện ở nghiệm thu v0.0.1 (kịch bản A4).
-- Idempotent (CREATE OR REPLACE / DROP TRIGGER IF EXISTS): chạy lại an toàn.
-- down: DROP TRIGGER IF EXISTS tasks_cancel ON work.tasks; DROP FUNCTION IF EXISTS agent.tasks_cancel_trg();  (không mất dữ liệu)
-- Chưa có core.schema_migrations: bảng ghi phiên bản đi cùng 0.1.0; tạm thời ghi lần áp dụng vào nhật ký vận hành.
BEGIN;
-- Việc bị hủy: dừng thẻ Kanban của nó (cầu nối archive thẻ). Thẻ chưa kịp tạo bên Kanban thì hủy lệnh dispatch đang chờ.
CREATE OR REPLACE FUNCTION agent.tasks_cancel_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE c agent.cards;
BEGIN
  IF NEW.status <> 'cancelled' OR OLD.status = 'cancelled' OR NEW.agent_id IS NULL THEN RETURN NEW; END IF;
  FOR c IN SELECT * FROM agent.cards WHERE task_id = NEW.id AND status NOT IN ('done','archived','gave_up','crashed','timed_out','cancelled') LOOP
    IF c.card_id IS NULL THEN
      UPDATE agent.outbox SET done_at = now(), error = 'Việc bị hủy trước khi tạo thẻ' WHERE card_ref = c.id AND kind = 'dispatch' AND done_at IS NULL;
    ELSE
      INSERT INTO agent.outbox (company_id, kind, task_id, card_ref, payload)
      VALUES (c.company_id, 'cancel', NEW.id, c.id, jsonb_build_object('board', c.board, 'card_id', c.card_id));
    END IF;
    UPDATE agent.cards SET status = 'cancelled', last_event_at = now() WHERE id = c.id;
  END LOOP;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tasks_cancel ON work.tasks;
CREATE TRIGGER tasks_cancel AFTER UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION agent.tasks_cancel_trg();
COMMIT;
