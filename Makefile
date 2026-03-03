PROJECT_ROOT := $(CURDIR)

.PHONY: setup-ios-runtime run-ios test-ios clean

setup-ios-runtime:
	@./scripts/ensure_ios_runtime.sh --download

run-ios:
	@./scripts/run_ios.sh run

test-ios:
	@./scripts/run_ios.sh test

clean:
	@rm -rf "$(PROJECT_ROOT)/.build"
