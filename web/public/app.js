// Tiện ích nhỏ, không phụ thuộc thư viện (CSP chỉ cho script cùng nguồn).
document.addEventListener('submit', (e) => {                       // xác nhận trước thao tác không đảo ngược
  const msg = e.target.getAttribute && e.target.getAttribute('data-confirm');
  if (msg && !window.confirm(msg)) e.preventDefault();
});
document.addEventListener('focusin', (e) => { if (e.target.matches && e.target.matches('[data-select]')) e.target.select(); });
const secs = Number(document.body.dataset.refresh || 0);          // trang theo dõi: tự tải lại khi không đang nhập liệu
if (secs > 0) setInterval(() => {
  const typing = document.activeElement && /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
  const dirty = [...document.querySelectorAll('textarea,input[type=text],input:not([type])')].some((el) => el.value);
  if (!document.hidden && !typing && !dirty) location.reload();
}, secs * 1000);
