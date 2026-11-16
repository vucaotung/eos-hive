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
linh_vuc: xây dựng
buoc: 06, 09
nguon: https://vbpl.vn/duong-dan-toi-van-ban
ngay_tra: 2000-03-01
---

# Chương I. TÊN CHƯƠNG

## Điều 1. Tên điều
1. Nội dung khoản 1.
   a) Nội dung điểm a.
   b) Nội dung điểm b.
2. Nội dung khoản 2.

## Điều 2. Tên điều
...
```

## Giá trị `tinh_trang`
`con_hieu_luc` · `het_mot_phan` (một số điều hết hiệu lực) · `het_hieu_luc` · `chua_hieu_luc`.

## Quy tắc soạn
- Giữ **đúng chữ** của bản chính thức, kể cả dấu và đánh số; không sửa lỗi chính tả của văn bản gốc (ghi chú vào báo cáo nếu thấy).
- Giữ cấu trúc Chương, Mục, Điều, Khoản, Điểm; mỗi Điều bắt đầu bằng `##`.
- Phụ lục, biểu mẫu: giữ dưới tiêu đề `# Phụ lục …`; bảng chuyển thành bảng Markdown, bảng quá phức tạp thì ghi "xem bản gốc" kèm link và nêu rõ trong báo cáo.
- Không thêm lời bình, tóm tắt, hay diễn giải vào thân văn bản.
- Văn bản dài: một tệp một văn bản (tối đa 5 MB). Không chia nhỏ theo chương.
