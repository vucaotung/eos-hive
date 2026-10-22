import { Button, Spinner, Toast } from "@heroui/react";
import { AppProvider, useApp } from "./lib/store.jsx";
import Shell from "./components/Shell.jsx";
import TaskDrawer from "./components/TaskDrawer.jsx";
import Login from "./pages/Login.jsx";
import Today from "./pages/Today.jsx";
import Tasks from "./pages/Tasks.jsx";
import Approvals from "./pages/Approvals.jsx";
import Projects from "./pages/Projects.jsx";
import Reports from "./pages/Reports.jsx";
import Admin from "./pages/Admin.jsx";
import Me from "./pages/Me.jsx";
import DriveSetup from "./pages/DriveSetup.jsx";
import { ErrorBox } from "./components/ui.jsx";

const PAGES = { today: Today, tasks: Tasks, projects: Projects, approvals: Approvals, reports: Reports, admin: Admin, me: Me };

function Gate() {
  const { me, meError, loadMe, route, signOut } = useApp();
  if (me === null) return <Login />;
  if (!me) {
    return (
      <div className="grid min-h-dvh place-items-center px-4">
        {meError ? (
          <div className="flex w-full max-w-md flex-col gap-3"><ErrorBox error={meError} onRetry={loadMe} /><Button variant="secondary" onPress={signOut}>Đăng nhập lại</Button></div>
        ) : <Spinner size="lg" aria-label="Đang tải" />}
      </div>
    );
  }
  // Bước bắt buộc lần đầu: khai báo thư mục Drive làm việc
  if (me.user?.drive_status === "none" && !sessionStorage.getItem("deo.skipDrive")) {
    return (
      <div className="mx-auto flex min-h-dvh max-w-2xl flex-col justify-center gap-5 px-4 py-10">
        <div>
          <p className="text-sm font-semibold text-muted">Chào {me.user.name}, còn một bước nữa</p>
          <h1 className="mt-1 text-3xl font-extrabold tracking-tight text-balance">Thiết lập thư mục làm việc trên Drive</h1>
        </div>
        <DriveSetup onDone={loadMe} />
        <button type="button" className="self-start text-sm font-semibold text-muted underline-offset-2 hover:underline"
          onClick={() => { sessionStorage.setItem("deo.skipDrive", "1"); loadMe(); }}>Làm sau, vào ứng dụng trước</button>
      </div>
    );
  }
  const Page = PAGES[route.page] || Today;
  return (
    <Shell>
      <Page />
      <TaskDrawer />
    </Shell>
  );
}

export default function App() {
  return (
    <AppProvider>
      <Toast.Provider placement="bottom" />
      <Gate />
    </AppProvider>
  );
}
