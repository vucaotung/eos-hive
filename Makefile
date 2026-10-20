# Dùng: make help
.DEFAULT_GOAL := help
help: ## Liệt kê lệnh
	@grep -E '^[a-z_-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
test-db: ## Dựng CSDL thử, chạy test lược đồ + agent (cần EOS_TEST_DSN)
	scripts/test_db.sh
test-mcp: ## Kiểm thử đầu–cuối máy chủ MCP (sau test-db)
	scripts/test_mcp.sh
test-web: ## Kiểm thử đầu–cuối giao diện web (Google giả lập)
	scripts/test_web.sh
test-bridge: ## Kiểm thử cầu nối với Hermes giả lập (cần postgrest)
	scripts/test_bridge.sh
test: test-db test-mcp test-web test-bridge ## Chạy cả bốn
acceptance: ## Nghiệm thu đầu–cuối trên MÁY THẬT (tốn LLM; ONLY=A1,A3 để chọn kịch bản)
	scripts/acceptance.sh $(if $(ONLY),--only $(ONLY))
audit: ## Kiểm toán bảo mật trên MÁY THẬT (chỉ đọc; checklist docs/06)
	scripts/security_audit.sh
restore-drill: ## Diễn tập khôi phục sao lưu vào Postgres rỗng trên Z2 (FRESH=1 để sao lưu mới trước)
	scripts/restore_drill.sh $(if $(FRESH),--fresh)
secrets: ## Quét bí mật trước khi commit
	scripts/check_secrets.sh
schema: ## Ghép db/*.sql thành eos-schema.sql
	scripts/build_schema.sh > eos-schema.sql
hooks: ## Cài hook pre-commit quét bí mật
	scripts/install_hooks.sh
