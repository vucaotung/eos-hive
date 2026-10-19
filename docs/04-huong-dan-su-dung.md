# 04 · Hướng dẫn sử dụng

> **Trạng thái v0.0.0:** các màn hình web chưa có (giai đoạn 1–2). Hướng dẫn dưới đây gồm phần **dùng được ngay** (agent cá nhân qua MCP) và phần **thiết kế đích** (đánh dấu 🔜) để người dùng biết hệ thống sẽ vận hành thế nào. Việc cấp mã MCP tạm thời do người vận hành làm bằng SQL (§2).

## 1. Khái niệm một trang

- **Việc** có mã `T-<số>`, một **người phụ trách** (chịu trách nhiệm, tính KPI), có thể có một **agent** thực hiện.
- Trạng thái: Cần làm → Đang làm → Vướng → Chờ duyệt → Xong (hoặc Hủy).
- **Chờ duyệt**: kết quả nằm đó cho người có thẩm quyền xem. Agent làm xong chỉ đưa việc tới đây; người mới đóng.
- **Vướng** kèm biểu tượng "agent đang hỏi": có câu hỏi cần bạn trả lời.
- Tệp của bạn nằm trong Drive của bạn. Hệ thống chỉ nhớ tên và link.

## 2. Nhân viên

### 2.1 Nối agent cá nhân của bạn vào hệ thống (MCP)

1. Nhờ người vận hành cấp **mã MCP** cho bạn. 🔜 Sau này: Tài khoản → Kết nối AI agent → Tạo mã. Chọn phạm vi tối thiểu bạn cần:

   | Phạm vi | Cho phép |
   | --- | --- |
   | `read` | Xem việc, tìm kiếm, công văn đến, hộp chờ duyệt |
   | `write` | Bình luận, cập nhật tiến độ, nộp kết quả |
   | `drive` | Lưu kết quả vào Drive của bạn |
   | `kb` | Liệt kê Kho dữ liệu chung bạn được hỏi |
   | `hr_self` | Xem công, phép, KPI **của chính bạn** |

2. Mã dạng `eos_…` (52 ký tự) hiện **một lần**. Cất vào trình quản lý mật khẩu. **Không gửi qua chat hay email, không dán vào tài liệu.**
3. Thêm máy chủ MCP vào agent của bạn:

   - Claude Code: `claude mcp add --transport http enterprise-os https://work.enterpriseos.bond/mcp --header "Authorization: Bearer eos_…"`
   - Máy khách khác hỗ trợ MCP qua HTTP: địa chỉ `https://work.enterpriseos.bond/mcp`, tiêu đề `Authorization: Bearer eos_…`. Mẫu JSON: `{"mcpServers":{"enterprise-os":{"type":"http","url":"https://work.enterpriseos.bond/mcp","headers":{"Authorization":"Bearer eos_…"}}}}`
   - Hermes riêng của bạn: khai trong `mcp_servers` của profile (kiểm cú pháp theo bản Hermes của bạn).
   - Claude.ai / ChatGPT bản web: **chưa nối được** (cần OAuth, xem `docs/08`).

4. Thử: bảo agent "gọi eos_whoami". Thấy tên bạn, công ty, phòng, trạng thái thư mục Drive là xong.

Mã có hạn tối đa 365 ngày, tối đa 5 mã còn hiệu lực. Mất thiết bị hay nghi lộ: nhờ vận hành **thu hồi ngay**.

### 2.2 Những câu nói với agent của bạn

| Bạn nói | Agent dùng |
| --- | --- |
| "Hôm nay tôi có gì?" | `eos_my_day` (việc hạn hôm nay, quá hạn, chờ tôi duyệt, agent đang hỏi, công văn đến) |
| "Cho tôi xem T-123" | `eos_get_task` (yêu cầu, bình luận, tệp, báo cáo của agent) |
| "Tìm việc liên quan đến hợp đồng Đại Bái" | `eos_search` (gõ không dấu cũng được) |
| "Làm T-123 giúp tôi rồi lưu vào Drive" | đọc việc → làm → `eos_save_to_drive` → hỏi bạn → `eos_submit_result` |
| "Cập nhật T-123 xong 60%" | `eos_update_progress` (tối đa 99% cho tới khi nộp) |
| "Trả lời agent trong T-123: áp dụng cho dự án Đại Bái" | `eos_comment` kind=answer |
| "Công văn đến mới tuần này" | `eos_incoming_list` (văn bản mật chỉ hiện số và ngày) |
| "Phép năm của tôi còn bao nhiêu?" | `eos_my_hr` (cần phạm vi `hr_self`) |

Hai lời nhắc dựng sẵn trong máy khách MCP: **lam_va_nop_viec** và **bao_cao_cuoi_ngay**.

### 2.3 Quy trình nhận–làm–nộp

1. Việc giao cho bạn → agent cá nhân (nếu bạn bật) thấy trong `eos_my_day`.
2. Làm; kết quả dài phải thành **tệp** trong Drive, không dán vào bình luận. Đường dẫn chuẩn: `Kết quả/<năm-tháng>/T-<số> - <tên>`.
3. Nộp bằng `eos_submit_result` kèm tóm tắt 2–6 câu: đã làm gì, kết quả chính, tệp nào, điều gì còn chưa chắc. **Agent phải hỏi bạn trước khi nộp.**
4. Việc có quy trình duyệt → sang **Chờ duyệt**; không có → **Xong**.

### 2.4 Những điều agent của bạn không làm được (đúng thiết kế)
Duyệt hay trả lại thay bạn; cấp số công văn; chốt lương; đổi vai trò; xóa dữ liệu; xem việc bạn không có quyền; đọc dữ liệu của người khác. Lỗi "Không có quyền" là bình thường — đừng bảo agent thử cách khác.

## 3. Trưởng phòng / người giao việc

- Giao việc cho **người**; có thể kèm agent thực hiện (🔜 chọn ở ô "Giao cho agent").
- Việc agent làm xong về **Chờ xem**: mở kết quả, đọc tóm tắt, căn cứ, mức tin cậy, rủi ro còn lại, tệp. Chọn:
  - **Chấp nhận** → Xong, KPI tính cho người phụ trách.
  - **Trả lại** kèm lý do cụ thể → agent làm lại (tối đa 2 lần). Lần trả thứ 3 việc về người phụ trách, agent dừng.
- **Agent đề xuất hành động mức L2** (ví dụ giao việc cho người khác, soạn công văn đi) → bạn nhận yêu cầu xác nhận, hết hạn sau 3 ngày. Không trả lời = hết hạn, agent không làm.
- **Agent đang hỏi** (Vướng): trả lời trong khung bình luận; agent tự chạy tiếp.
- Việc lớn → giao cho **Điều phối**: nó chia tối đa 8 việc con cho Văn thư / Nhân sự / Quản trị dữ liệu theo thứ tự, rồi gom một bản tổng hợp cho bạn duyệt. Bạn chỉ duyệt bản tổng hợp.

## 4. Quản trị công ty

| Việc | Cách làm |
| --- | --- |
| Bật agent cho công ty | chạy `deploy/setup_agents.sql` (🔜 màn hình Quản trị → Agent) |
| Chọn agent nào được tự hoàn tất | `agent.company_agents.auto_done` (mặc định tắt: luôn cần người duyệt) |
| Số lần làm lại tối đa | `agent.company_settings.max_rework` (mặc định 2) |
| Người duyệt mặc định | `agent.company_settings.default_reviewer` |
| Xem nhật ký agent và MCP | `agent.events`, `agent.mcp_calls`, `core.audit_log` ("người đó, qua MCP/agent") |
| Thu hồi mã của một người | `docs/03` §4.2 |

Khuyến nghị: để `auto_done` tắt cho **mọi** agent ít nhất 30 ngày đầu; chỉ bật cho loại việc nhàm chán, đã đạt tỷ lệ chấp nhận cao.

## 5. Theo phân hệ (khi màn hình có)

- **Công văn** 🔜: Văn thư AI đọc công văn đến, điền nháp sổ (trích yếu, nơi gửi, độ khẩn), đề xuất người xử lý; **người** cấp số và bấm vào sổ. Văn bản mật: người tự nhập, hệ thống không số hóa.
- **Nhân sự** 🔜: Nhân sự AI rà chấm công bất thường, đối chiếu đơn nghỉ với số phép, nháp KPI/bảng lương; **người** chốt lương.
- **Kho dữ liệu chung** 🔜: Quản trị dữ liệu AI trả lời có trích dẫn (tên tài liệu, trang). Câu không tìm thấy được gom lại để bổ sung tài liệu.

## 6. Người vận hành
Xem `docs/03`. Sự cố: `docs/05`.

## 7. Cấp mã MCP tạm thời bằng SQL (người vận hành)

Chạy trên VPS 169, **không** ghi lịch sử shell (`HISTCONTROL=ignorespace`, thêm dấu cách đầu dòng):

    BEGIN;
    SELECT set_config('request.jwt.claims', '{"sub":"<uuid-người-dùng>"}', true);
    SELECT agent.mcp_token_issue('Claude của Minh', 'claude', '{read,write,drive}', 90);
    COMMIT;

Kết quả `eos_…` đưa cho đúng người qua kênh an toàn (gặp trực tiếp, trình quản lý mật khẩu chia sẻ). Hàm từ chối nếu người đã có 5 mã còn hạn. Vòng đời mã: `agent.mcp_tokens` (chỉ có băm).
