-- 0002 · Chuẩn hóa agent.reports.confidence. Phát hiện ở nghiệm thu A6: worker nộp confidence=1 và 'high',
-- ràng buộc chỉ cho cao|trung_binh|thap -> ingest_event lỗi 23514, cầu nối thử lại vô hạn, việc con không bao giờ Xong.
-- Idempotent. down: DROP TRIGGER IF EXISTS reports_norm_confidence ON agent.reports; DROP FUNCTION IF EXISTS agent.reports_norm_trg(); DROP FUNCTION IF EXISTS agent._norm_confidence(text);
BEGIN;
-- Chuẩn hóa độ tin cậy do agent (LLM) tự điền: 'cao' | 'trung_binh' | 'thap'; giá trị lạ -> NULL thay vì làm hỏng cả báo cáo.
CREATE OR REPLACE FUNCTION agent._norm_confidence(v text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s text := lower(btrim(coalesce(v, ''))); n numeric;
BEGIN
  IF s = '' THEN RETURN NULL; END IF;
  IF s IN ('cao', 'high', 'chắc chắn', 'chac chan') THEN RETURN 'cao'; END IF;
  IF s IN ('trung_binh', 'trung bình', 'trung binh', 'tb', 'medium', 'mid', 'vừa', 'vua') THEN RETURN 'trung_binh'; END IF;
  IF s IN ('thap', 'thấp', 'low') THEN RETURN 'thap'; END IF;
  IF s ~ '^[0-9]+(\.[0-9]+)?%?$' THEN
    n := replace(s, '%', '')::numeric;
    IF right(s, 1) = '%' OR n > 10 THEN n := n / 100;     -- 85 hoặc 85% -> 0,85
    ELSIF n > 1 THEN RETURN NULL;                           -- 2..10: thang điểm không rõ
    END IF;
    RETURN CASE WHEN n >= 0.75 THEN 'cao' WHEN n >= 0.4 THEN 'trung_binh' ELSE 'thap' END;
  END IF;
  RETURN NULL;
END $$;
CREATE OR REPLACE FUNCTION agent.reports_norm_trg() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.confidence := agent._norm_confidence(NEW.confidence);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS reports_norm_confidence ON agent.reports;
CREATE TRIGGER reports_norm_confidence BEFORE INSERT OR UPDATE OF confidence ON agent.reports
  FOR EACH ROW EXECUTE FUNCTION agent.reports_norm_trg();
COMMIT;
