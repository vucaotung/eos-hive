# Mẫu Markdown văn bản pháp luật để nạp

Tên tệp do máy chủ đặt theo số hiệu không dấu. Front matter: mỗi khóa một dòng, `khóa: giá trị`. Ngày dạng `YYYY-MM-DD`. `nguon` là đường dẫn https tới trang **chính thống** (vbpl.vn, Công báo, cổng chinhphu.vn, *.gov.vn…). Mọi giá trị dưới đây là **ví dụ về định dạng**, không phải văn bản thật.

```markdown
---
so_hieu: <số>/<năm>/<loại>-<cơ quan>
ten: Tên đầy đủ của văn bản như trên bản chính thức
loai: nghị định
co_quan: Cơ quan ban hành
ngay_ban_hanh: 2000-01-01
ngay_hieu_luc: 2000-02-01
tinh_trang: con_hieu_luc
thay_the:
sua_doi:
dan_chieu:
linh_vuc: xây dựng
buoc: 06, 09
nguon: https://vbpl.vn/duong-dan-toi-van-ban
ngay_tra: 2000-03-01
---

# Chương I. TÊN CHƯƠNG

## Mục 1. TÊN MỤC

### Điều 1. Tên điều

1. Nội dung khoản 1.

a) Nội dung điểm a;

b) Nội dung điểm b.

2. Nội dung khoản 2.

### Điều 2. Tên điều

...

# Phụ lục I. TÊN PHỤ LỤC

| Cột | Cột |
|---|---|
| … | … |
```

## Giá trị `tinh_trang`
`con_hieu_luc` · `het_mot_phan` (một số điều hết hiệu lực) · `het_hieu_luc` · `chua_hieu_luc`.

## Quy tắc soạn
- Giữ **đúng chữ** của bản chính thức, kể cả dấu và đánh số; không sửa lỗi chính tả của văn bản gốc (ghi chú vào báo cáo nếu thấy).
- Cấu trúc là quan trọng nhất: `#` Chương và Phụ lục, `##` Mục, `###` Điều (kèm tên điều); khoản (`1.`) và điểm (`a)`) mỗi cái một đoạn riêng, **không thụt lề**. Văn bản không chia chương thì Điều vẫn dùng `###`. Đây cũng là cấu trúc `eos_law_save_from_source` tạo ra.
- Không ghi số trang, tiêu đề hay chân trang của bản in; đoạn bị cắt khi sang trang phải nối lại.
- Văn bản được dẫn chiếu (căn cứ, thay thế, sửa đổi, dẫn chiếu trong điều): ghi số hiệu vào `dan_chieu` (cách nhau dấu phẩy); `thay_the`, `sua_doi` vẫn ghi riêng.
- Phụ lục, biểu mẫu: giữ dưới tiêu đề `# Phụ lục …`; bảng chuyển thành bảng Markdown, bảng quá phức tạp thì ghi "xem bản gốc" kèm link và nêu rõ trong báo cáo.
- Không thêm lời bình, tóm tắt, hay diễn giải vào thân văn bản.
- Văn bản dài: một tệp một văn bản (tối đa 5 MB). Không chia nhỏ theo chương.
