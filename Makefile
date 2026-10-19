# Dùng: make help
.DEFAULT_GOAL := help
help: ## Liệt kê lệnh
	@grep -E '^[a-z_-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
test-db: ## Dựng CSDL thử, chạy test lược đồ + agent (cần EOS_TEST_DSN)
	scripts/test_db.sh
test-mcp: ## Kiểm thử đầu–cuối máy chủ MCP (sau test-db)
	scripts/test_mcp.sh
test-bridge: ## Kiểm thử cầu nối với Hermes giả lập (cần postgrest)
	scripts/test_bridge.sh
test: test-db test-mcp test-bridge ## Chạy cả ba
secrets: ## Quét bí mật trước khi commit
	scripts/check_secrets.sh
schema: ## Ghép db/*.sql thành eos-schema.sql
	scripts/build_schema.sh > eos-schema.sql
hooks: ## Cài hook pre-commit quét bí mật
	scripts/install_hooks.sh
