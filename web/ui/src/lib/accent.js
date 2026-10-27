// Màu chủ đạo thay thế (Cài đặt). Giá trị đã ĐO tương phản WCAG 2.x bằng tập lệnh trong docs/18 (nền oklch → sRGB):
// accent/nền ≥ 4.5, chữ nhỏ `act` trên accent-soft và trên bề mặt ≥ 4.5, chữ trên nút đặc ≥ 4.5; thấp nhất 5,42. Màu mặc định (tím) nằm trong app.css.
export const ACCENTS = {
  default: { label: "Tím", swatch: "#9184d9" },
  blue: { label: "Lam", dark: { accent: "#60a7d6", act: "#9bcff4", soft: "#2d3a4c", fg: "#161826" }, light: { accent: "#176297", act: "#1d4e74", soft: "#e0e9f1", fg: "#ffffff" } },
  teal: { label: "Ngọc", dark: { accent: "#5bb7ac", act: "#9bddd3", soft: "#2c3c45", fg: "#161826" }, light: { accent: "#006662", act: "#124f4c", soft: "#ddeaeb", fg: "#ffffff" } },
  bronze: { label: "Đồng", dark: { accent: "#cf976a", act: "#efc4a2", soft: "#3e373b", fg: "#161826" }, light: { accent: "#8a542d", act: "#6c452a", soft: "#eee7e5", fg: "#ffffff" } },
};
for (const k of ["blue", "teal", "bronze"]) ACCENTS[k].swatch = ACCENTS[k].dark.accent;

const VARS = ["--accent", "--act", "--accent-soft", "--accent-foreground"];
export const effectiveTheme = () => document.documentElement.getAttribute("data-theme") || (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");

export function applyAccent(key) {
  const el = document.documentElement.style;
  const a = ACCENTS[key];
  if (!a || key === "default") { VARS.forEach((v) => el.removeProperty(v)); return; }
  const t = a[effectiveTheme()];
  el.setProperty("--accent", t.accent); el.setProperty("--act", t.act); el.setProperty("--accent-soft", t.soft); el.setProperty("--accent-foreground", t.fg);
}
