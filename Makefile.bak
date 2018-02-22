# Copyright (c) 2017 SUSE LLC

# ==============================================================================
# Test targets
.PHONY: lint test.staging

lint:
	flake8

test.staging:
	DEBUG=1 tests/stage-test/test_staging.sh

# ==============================================================================
# Help

.PHONY: help
help:
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Targets:'
	@echo '    lint:              Lint the source code.'
	@echo '    test.staging:      Perform staging integration test.'
