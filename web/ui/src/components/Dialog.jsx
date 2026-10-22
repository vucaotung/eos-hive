import { useState } from "react";
import { Button, Modal, toast } from "@heroui/react";
import { ErrorBox } from "./ui.jsx";

export function Dialog({ title, isOpen, onClose, onSave, busy, error, children, saveLabel = "Lưu" }) {
  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-lg">
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>{title}</Modal.Heading></Modal.Header>
          <Modal.Body><form className="flex flex-col gap-4" onSubmit={(e) => { e.preventDefault(); onSave(); }}>{children}<button type="submit" hidden /></form>
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}</Modal.Body>
          <Modal.Footer><Button variant="secondary" onPress={onClose}>Hủy</Button><Button isPending={busy} onPress={onSave}>{saveLabel}</Button></Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}

export function useEditor(initial) {
  const [open, setOpen] = useState(false), [f, setF] = useState(initial), [busy, setBusy] = useState(false), [error, setError] = useState(null);
  return {
    open, f, busy, error, set: (k) => (v) => setF((s) => ({ ...s, [k]: v })),
    start: (v = initial) => { setF(v); setError(null); setOpen(true); }, close: () => setOpen(false),
    run: async (fn, ok) => { setBusy(true); setError(null); try { await fn(); toast.success(ok); setOpen(false); } catch (e) { setError(e); } finally { setBusy(false); } },
  };
}
