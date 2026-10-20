# Cách ký của Valnex (mô hình công ty) — cho Văn thư AI

Nguyên tắc: **người giao việc quyết định ai ký**. Văn thư AI chỉ ghi đúng hình thức ký tương ứng vào dự thảo. Không nói rõ người ký thì `kanban_block` hỏi.

| Người ký | `cap_ky` | `chuc_vu_cap_tren` | `chuc_vu_ky` | Khối chữ ký hiện ra |
| --- | --- | --- | --- | --- |
| Giám đốc / Tổng giám đốc ký trực tiếp | `""` | (bỏ trống) | `GIÁM ĐỐC` | `GIÁM ĐỐC` |
| Phó giám đốc ký thay Giám đốc | `KT` | `GIÁM ĐỐC` | `PHÓ GIÁM ĐỐC` | `KT. GIÁM ĐỐC` / `PHÓ GIÁM ĐỐC` |
| Trưởng phòng ký thừa lệnh Giám đốc (có quyết định/giấy ủy quyền) | `TL` | `GIÁM ĐỐC` | `TRƯỞNG PHÒNG <tên phòng>` | `TL. GIÁM ĐỐC` / `TRƯỞNG PHÒNG …` |
| Ký thừa ủy quyền (người được ủy quyền, có văn bản ủy quyền) | `TUQ` | `GIÁM ĐỐC` | chức vụ người được ủy quyền | `TUQ. GIÁM ĐỐC` / chức vụ |
| Ký thay mặt tập thể (Hội đồng thành viên, Ban kiểm soát…) | `TM` | `HỘI ĐỒNG THÀNH VIÊN` | `CHỦ TỊCH` | `TM. HỘI ĐỒNG THÀNH VIÊN` / `CHỦ TỊCH` |

## Cách dùng
- Giám đốc ký trực tiếp: **không** có tiền tố TM./KT./TL./TUQ.
- `KT.` chỉ cho cấp phó ký thay người đứng đầu khi được giao.
- `TL.` và `TUQ.` cần có văn bản/quyết định ủy quyền: ghi vào `residual_risk` "cần đính kèm văn bản ủy quyền" nếu người giao chưa nói đã có.
- Viết `chuc_vu_cap_tren` và `chuc_vu_ky` đúng như chức danh thật của Valnex theo người giao; công cụ tự IN HOA.
- Họ tên chưa biết thì để trống `nguoi_ky`.

## Lưu ý
Ma trận Bộ trưởng/Thứ trưởng/Vụ trưởng ở trang nguồn là của một bộ, **không dùng** cho Valnex. Nếu Valnex đổi cơ cấu chức danh, cập nhật tệp này (và `docs/09`).
