PROJECT_ROOT := $(CURDIR)

.PHONY: setup-ios-runtime run-ios test-ios run-app-server clean

setup-ios-runtime:
	@./scripts/ensure_ios_runtime.sh --download

run-ios:
	@./scripts/run_ios.sh run

test-ios:
	@./scripts/run_ios.sh test

run-app-server:
	@./scripts/run_app_server_stack.sh

clean:
	@rm -rf "$(PROJECT_ROOT)/.build"
