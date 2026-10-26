import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { rpc, getMe, logout, onUnauthorized } from "./api.js";

const Ctx = createContext(null);
export const useApp = () => useContext(Ctx);

// Định tuyến bằng hash: #/today, #/tasks, #/approvals, #/reports, #/admin, #/me, #/login?e=...&code=...
function readRoute() {
  const h = location.hash.replace(/^#\/?/, "");
  const [page, query = ""] = h.split("?");
  return { page: page || "today", params: Object.fromEntries(new URLSearchParams(query)) };
}
export function go(page, params) {
  const q = params ? new URLSearchParams(params).toString() : "";
  location.hash = `#/${page}${q ? `?${q}` : ""}`;
}

const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* bỏ qua */ } },
};

export function AppProvider({ children }) {
  const [me, setMe] = useState(undefined);              // undefined: đang tải · null: chưa đăng nhập
  const [meError, setMeError] = useState(null);
  const [companyId, setCompanyId] = useState(store.get("deo.company"));
  const [route, setRoute] = useState(readRoute());
  const [org, setOrg] = useState({ departments: [], members: [], projects: [], project_members: [], flows: [] });
  const [version, setVersion] = useState(0);            // tăng để các trang tải lại dữ liệu
  const [theme, setThemeState] = useState(() => { const v = store.get("deo.theme"); return v === "system" ? "" : (v || "dark"); });   // mặc định chế độ tối (Nocturne); "" = theo hệ thống

  useEffect(() => { const f = () => setRoute(readRoute()); addEventListener("hashchange", f); return () => removeEventListener("hashchange", f); }, []);
  useEffect(() => onUnauthorized(() => setMe(null)), []);
  useEffect(() => {
    const el = document.documentElement;
    if (theme) el.setAttribute("data-theme", theme); else el.removeAttribute("data-theme");
    store.set("deo.theme", theme || "system");
  }, [theme]);

  const loadMe = useCallback(async () => {
    try { const m = await getMe(); setMe(m); setMeError(null); return m; }
    catch (e) { if (e.status === 401) { setMe(null); setMeError(null); } else setMeError(e); return null; }
  }, []);
  useEffect(() => { loadMe(); }, [loadMe]);

  const signOut = useCallback(async () => {
    try { await logout(); } catch { /* đã hết phiên */ }
    store.set("deo.company", null); setMe(null); setOrg({ departments: [], members: [], projects: [], project_members: [], flows: [] }); location.hash = "#/login";
  }, []);

  // Chọn công ty hiện hành
  const memberships = me?.memberships || [];
  const membership = memberships.find((m) => m.company_id === companyId) || memberships[0] || null;
  useEffect(() => { if (membership && membership.company_id !== companyId) setCompanyId(membership.company_id); }, [membership, companyId]);
  const switchCompany = (id) => { setCompanyId(id); store.set("deo.company", id); setVersion((v) => v + 1); };
  useEffect(() => { if (companyId) store.set("deo.company", companyId); }, [companyId]);

  const loadOrg = useCallback(async () => {
    if (!membership) return;
    const o = await rpc("app_org", { company_id: membership.company_id });
    setOrg({ ...o, members: o.members.sort((a, b) => (a.user?.name || "").localeCompare(b.user?.name || "", "vi")) });
  }, [membership]);
  useEffect(() => { loadOrg().catch(() => {}); }, [loadOrg, version]);

  const refresh = useCallback(() => setVersion((v) => v + 1), []);
  // Việc đang mở nằm trên URL (#/trang?t=37): sao chép link là mở thẳng việc; nút Back đóng ngăn chi tiết.
  const openTaskId = /^\d{1,12}$/.test(route.params.t || "") ? Number(route.params.t) : null;
  const openTask = useCallback((id) => {
    const r = readRoute(), params = { ...r.params };
    if (id) params.t = String(id); else delete params.t;
    go(r.page, Object.keys(params).length ? params : undefined);
  }, []);

  const value = useMemo(() => {
    const role = membership?.role || null;
    const lookups = {
      dept: Object.fromEntries(org.departments.map((d) => [d.id, d])),
      person: Object.fromEntries(org.members.filter((m) => m.user).map((m) => [m.user.id, m.user])),
      project: Object.fromEntries(org.projects.map((p) => [p.id, p])),
      flow: Object.fromEntries(org.flows.map((f) => [f.id, f])),
      agent: Object.fromEntries((me?.agents || []).map((a) => [a.code, a])),
    };
    return {
      me, meError, loadMe, signOut, route, go,
      memberships, membership, companyId: membership?.company_id || null, switchCompany,
      role, isAdmin: role === "owner" || role === "admin", isManager: role === "manager", isSystemAdmin: !!me?.user?.is_system_admin,
      org, lookups, loadOrg, version, refresh,
      openTaskId, openTask, theme, setTheme: setThemeState,
      userId: me?.user?.id || null,
    };
  }, [me, meError, loadMe, signOut, route, memberships, membership, org, loadOrg, version, refresh, openTaskId, openTask, theme]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

// Hook tải dữ liệu đơn giản, tự tải lại khi version đổi
export function useLoad(fn, deps = []) {
  const { version } = useApp();
  const [state, setState] = useState({ data: null, error: null, loading: true });
  useEffect(() => {
    let alive = true;
    setState((s) => ({ ...s, loading: true }));
    fn().then((data) => alive && setState({ data, error: null, loading: false }))
        .catch((error) => alive && setState({ data: null, error, loading: false }));
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, ...deps]);
  return state;
}
