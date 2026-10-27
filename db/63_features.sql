-- =====================================================================
-- Enterprise OS — 63 Tính năng giao diện mới (thông báo, việc định kỳ, chi tiết việc, tạo việc bằng AI)
-- Chạy sau 62. Mỗi PHẦN được chép nguyên vào một migration (0026…) và áp dụng được nhiều lần.
-- =====================================================================
SET search_path = agent, work, core, public;

-- ==== PHẦN A: THÔNG BÁO (chuông) ====
-- Thông báo trong app cho: được giao việc, được nhắc tên (@), có bình luận ở việc của mình/đang theo dõi, đến lượt duyệt, việc hoàn thành.
-- Sự kiện của agent (agent_question, agent_result, agent_error...) đã có sẵn ở agent._notify; hàm đó nay cũng điền actor/is_ai.
CREATE OR REPLACE FUNCTION agent._notify(p_company uuid, p_user uuid, p_kind text, p_title text, p_task bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = core, public AS $$
  INSERT INTO core.notifications (company_id, user_id, kind, title, link, entity_type, entity_id, is_ai, actor)
  SELECT p_company, p_user, p_kind, p_title, '#/tasks?t=' || p_task, 'task', p_task::text, p_kind LIKE 'agent\_%', CASE WHEN p_kind LIKE 'agent\_%' THEN 'agent' END WHERE p_user IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION agent._notify_from(p_company uuid, p_user uuid, p_kind text, p_title text, p_body text, p_task bigint, p_actor text, p_ai boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = core, public AS $$
  INSERT INTO core.notifications (company_id, user_id, kind, title, body, link, entity_type, entity_id, actor, is_ai)
  SELECT p_company, p_user, p_kind, left(p_title, 300), left(p_body, 300), '#/tasks?t=' || p_task, 'task', p_task::text, p_actor, p_ai WHERE p_user IS NOT NULL
$$;

-- Người thực hiện thao tác hiện tại (từ claims): (actor, là AI?)
CREATE OR REPLACE FUNCTION agent._who() RETURNS TABLE (uid uuid, actor text, ai boolean, name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, public AS $$
  SELECT u.id, CASE WHEN u.kind = 'agent' THEN 'agent:' || coalesce((SELECT g.code FROM agent.agents g WHERE g.user_id = u.id), 'agent') ELSE 'user:' || u.id END, u.kind = 'agent', u.name
    FROM core.users u WHERE u.id = core.current_user_id()
  UNION ALL SELECT NULL, 'system', false, 'Hệ thống' WHERE core.current_user_id() IS NULL
$$;

CREATE OR REPLACE FUNCTION agent.notify_task_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE w record; watcher uuid;
BEGIN
  SELECT * INTO w FROM agent._who();
  IF TG_OP = 'INSERT' THEN
    IF NEW.assignee_id IS NOT NULL AND NEW.assignee_id IS DISTINCT FROM w.uid AND NEW.source <> 'agent' THEN
      PERFORM agent._notify_from(NEW.company_id, NEW.assignee_id, 'task_assigned', coalesce(w.name, 'Ai đó') || ' giao cho bạn: ' || NEW.title, NULL, NEW.id, w.actor, coalesce(w.ai, false));
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.assignee_id IS NOT NULL AND NEW.assignee_id IS DISTINCT FROM OLD.assignee_id AND NEW.assignee_id IS DISTINCT FROM w.uid AND NEW.source <> 'agent' THEN
    PERFORM agent._notify_from(NEW.company_id, NEW.assignee_id, 'task_assigned', coalesce(w.name, 'Ai đó') || ' giao cho bạn: ' || NEW.title, NULL, NEW.id, w.actor, coalesce(w.ai, false));
  END IF;
  IF NEW.status = 'done' AND OLD.status IS DISTINCT FROM 'done' THEN   -- việc xong: báo người giao và người theo dõi (trừ người vừa làm)
    FOR watcher IN SELECT DISTINCT x FROM unnest(ARRAY[NEW.created_by] || coalesce((SELECT array_agg(tw.user_id) FROM work.task_watchers tw WHERE tw.task_id = NEW.id), '{}')) x LOOP
      IF watcher IS NOT NULL AND watcher IS DISTINCT FROM w.uid AND NEW.source <> 'agent' THEN
        PERFORM agent._notify_from(NEW.company_id, watcher, 'task_done', 'Đã hoàn thành: ' || NEW.title, NULL, NEW.id, w.actor, coalesce(w.ai, false));
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tasks_notify ON work.tasks;
CREATE TRIGGER tasks_notify AFTER INSERT OR UPDATE OF assignee_id, status ON work.tasks FOR EACH ROW EXECUTE FUNCTION agent.notify_task_trg();

CREATE OR REPLACE FUNCTION agent.notify_comment_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE t work.tasks; ai boolean := NEW.actor LIKE 'agent:%'; who text; seen uuid[] := ARRAY[NEW.user_id]; u record;
BEGIN
  IF NEW.kind IN ('system','claim') THEN RETURN NEW; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = NEW.task_id;
  IF t.id IS NULL OR t.source = 'agent' AND NEW.actor LIKE 'agent:%' THEN RETURN NEW; END IF;   -- bình luận nội bộ giữa các agent: không báo người
  who := CASE WHEN ai THEN coalesce((SELECT g.name FROM agent.agents g WHERE g.code = substring(NEW.actor from 7)), 'Agent AI') ELSE coalesce((SELECT name FROM core.users WHERE id = NEW.user_id), 'Ai đó') END;
  -- 1. nhắc tên: @Họ tên của thành viên trong công ty (không phân biệt hoa thường); người nhắc không tự nhận thông báo
  FOR u IN SELECT m.user_id, us.name FROM core.memberships m JOIN core.users us ON us.id = m.user_id
            WHERE m.company_id = t.company_id AND m.active AND us.kind = 'person' AND position(lower('@' || us.name) in lower(NEW.body)) > 0 LOOP
    IF u.user_id IS DISTINCT FROM NEW.user_id THEN
      PERFORM agent._notify_from(t.company_id, u.user_id, 'mention', who || ' nhắc bạn ở T-' || t.id || ': ' || t.title, NEW.body, t.id, CASE WHEN ai OR NEW.user_id IS NULL THEN NEW.actor ELSE 'user:' || NEW.user_id END, ai);
      seen := seen || u.user_id;
    END IF;
  END LOOP;
  -- 2. bình luận ở việc của mình / đang theo dõi (người đã được báo vì nhắc tên thì bỏ qua); chỉ ghi chú, trả lời, kết quả: không báo từng câu hỏi/nộp (đã có thông báo riêng)
  IF NEW.kind IN ('note','answer','result') THEN
    FOR u IN SELECT DISTINCT x AS user_id FROM unnest(ARRAY[t.assignee_id, t.created_by] || coalesce((SELECT array_agg(tw.user_id) FROM work.task_watchers tw WHERE tw.task_id = t.id), '{}')) x LOOP
      IF u.user_id IS NOT NULL AND NOT (u.user_id = ANY (seen)) THEN
        PERFORM agent._notify_from(t.company_id, u.user_id, 'comment', who || ' bình luận ở T-' || t.id || ': ' || t.title, NEW.body, t.id, CASE WHEN ai OR NEW.user_id IS NULL THEN NEW.actor ELSE 'user:' || NEW.user_id END, ai);
        seen := seen || u.user_id;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS comments_notify ON work.comments;
CREATE TRIGGER comments_notify AFTER INSERT ON work.comments FOR EACH ROW EXECUTE FUNCTION agent.notify_comment_trg();

-- Đến lượt duyệt: người được chỉ định cụ thể (approver_user) nhận thông báo; người duyệt theo vai trò xem ở màn Duyệt
CREATE OR REPLACE FUNCTION agent.notify_decision_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE r core.approval_requests; t work.tasks; w record;
BEGIN
  IF NEW.decision <> 'pending' OR NEW.approver_user IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO r FROM core.approval_requests WHERE id = NEW.request_id;
  IF r.entity_type <> 'task' OR NEW.approver_user IS NOT DISTINCT FROM core.current_user_id() THEN RETURN NEW; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = r.entity_id;
  SELECT * INTO w FROM agent._who();
  IF t.id IS NOT NULL THEN PERFORM agent._notify_from(t.company_id, NEW.approver_user, 'approval_waiting', 'Chờ bạn duyệt (' || NEW.step_name || '): ' || t.title, NULL, t.id, w.actor, coalesce(w.ai, false)); END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS decisions_notify ON core.approval_decisions;
CREATE TRIGGER decisions_notify AFTER INSERT ON core.approval_decisions FOR EACH ROW EXECUTE FUNCTION agent.notify_decision_trg();

-- RPC cho chuông: danh sách + số chưa đọc; đánh dấu đã đọc
CREATE OR REPLACE FUNCTION agent.app_notifications(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); f text := coalesce(p->>'filter', 'all'); lim int := least(greatest(coalesce((p->>'limit')::int, 20), 1), 50);
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF f NOT IN ('all','mention','ai') THEN RAISE EXCEPTION 'Bộ lọc không hợp lệ'; END IF;
  RETURN jsonb_build_object(
    'unread', (SELECT count(*) FROM core.notifications n WHERE n.user_id = me.id AND n.company_id = cid AND n.read_at IS NULL),
    'items', coalesce((SELECT jsonb_agg(x ORDER BY (x->>'id')::bigint DESC) FROM (
       SELECT jsonb_build_object('id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'task', CASE WHEN n.entity_type = 'task' THEN n.entity_id::bigint END,
              'at', n.created_at, 'read', n.read_at IS NOT NULL, 'ai', n.is_ai,
              'who', CASE WHEN n.actor LIKE 'user:%' THEN (SELECT name FROM core.users WHERE id = substring(n.actor from 6)::uuid)
                          WHEN n.actor LIKE 'agent:%' THEN (SELECT g.name FROM agent.agents g WHERE g.code = substring(n.actor from 7)) END) AS x
         FROM core.notifications n
        WHERE n.user_id = me.id AND n.company_id = cid AND (f = 'all' OR (f = 'mention' AND n.kind = 'mention') OR (f = 'ai' AND n.is_ai))
        ORDER BY n.id DESC LIMIT lim) q), '[]'));
END $$;

CREATE OR REPLACE FUNCTION agent.app_notifications_read(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); n int;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF coalesce((p->>'all')::boolean, false) THEN
    UPDATE core.notifications SET read_at = now() WHERE user_id = me.id AND company_id = cid AND read_at IS NULL;
  ELSE
    UPDATE core.notifications SET read_at = now() WHERE user_id = me.id AND company_id = cid AND read_at IS NULL AND id IN (SELECT jsonb_array_elements_text(coalesce(p->'ids', '[]'))::bigint);
  END IF;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('marked', n);
END $$;
-- ==== HẾT PHẦN A ====

-- Quyền
GRANT EXECUTE ON FUNCTION agent.app_notifications(jsonb), agent.app_notifications_read(jsonb) TO web_svc;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;   -- hàm mới không mặc định chạy được bởi PUBLIC (xem kiểm thử "PUBLIC còn chạy được")
