# Copyright (c) 2017 SUSE LLC

# ==============================================================================
# Test targets
.PHONY: lint stage-test

lint:
	flake8

stage-test:
	DEBUG=1 tests/stage-test/test_staging.sh

# ==============================================================================
# Help

.PHONY: help
help:
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Targets:'
	@echo '    lint:              Lint the source code.'
	@echo '    stage-test:        Perform stageing integration test.'
