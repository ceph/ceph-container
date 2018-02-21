# Copyright (c) 2017 SUSE LLC
# Copyright 2016 The Rook Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# Build tunables
#
# FLAVORS_TO_BUILD - The images to build and from ceph-container sources:
# [ceph rel name]@[arch]@[os name]@[os version]@[base os registry]@[base os repo]@[base os tag]
#  - ceph rel name = named ceph version (e.g., luminous, mimic)
#  - arch = architecture of packages built (e.g., amd64, arm32, arm64)
#  - os name = directory name for the os used by ceph-container (e.g., ubuntu)
#  - os version = directory name for the os version used by ceph-container (e.g., 16.04 for above)
#  - base os registry = underscore (_) for default amd64; arm32v7 for arm32; arm64v8 for arm64, ...
#  - bases os repo = The repo to use for the basest base container. generally this is also the
#                    os name (e.g., ubuntu) but could be something like 'alpine'
#  - base os tag = Tagged version of the base os to use (e.g., ubuntu:16.04, alpine:3.6)
# e.g., luminous@amd64@ubuntu@16.04@_@ubuntu@16.04
#       luminous@arm64@ubuntu@16.04@arm64v8@ubuntu@16.04

FLAVORS_TO_BUILD ?= \
  luminous@x86_64@centos@7@_@centos@7 \
	luminous@amd64@ubuntu@16.04@_@ubuntu@16.04
#	luminous@amd64@opensuse@42.3@_@opensuse@42.3 \

IMAGES_TO_BUILD := daemon-base daemon

REGISTRY ?= ceph

# ==============================================================================
# Build targets
.PHONY: all stage build clean push

all: build

setvars.%:
	$(eval export CEPH_VERSION := $(word 1, $(subst @, ,$*)))
	$(eval export ARCH := $(word 2, $(subst @, ,$*)))
	$(eval export OS_NAME := $(word 3, $(subst @, ,$*)))
	$(eval export OS_VERSION := $(word 4, $(subst @, ,$*)))
	$(eval export BASEOS_REG := $(word 5, $(subst @, ,$*)))
	$(eval export BASEOS_REPO := $(word 6, $(subst @, ,$*)))
	$(eval export BASEOS_TAG := $(word 7, $(subst @, ,$*)))
	$(eval export IMAGES_TO_BUILD := $(IMAGES_TO_BUILD))
	$(eval export STAGING_DIR := staging-$(CEPH_VERSION)-$(BASEOS_REPO)-$(BASEOS_TAG)-$(ARCH))
	$(eval export BASE_IMAGE := $(BASEOS_REG)/$(BASEOS_REPO):$(BASEOS_TAG))
# Strip _/ from  beginning if exists
	$(eval export BASE_IMAGE := $(patsubst _/%,%,$(BASE_IMAGE)))
	$(eval export DAEMON_BASE_IMAGE := \
		$(REGISTRY)/daemon-base:$(CEPH_VERSION)-$(BASEOS_REPO)-$(BASEOS_TAG)-$(ARCH))
	$(eval export DAEMON_IMAGE := \
		$(REGISTRY)/daemon:$(CEPH_VERSION)-$(BASEOS_REPO)-$(BASEOS_TAG)-$(ARCH))
	@true

stage.%: setvars.%
	@sh -c ./stage.py

daemon-base.%: setvars.%
	@$(MAKE) -C $(STAGING_DIR)/daemon-base $(MAKECMDGOALS)

daemon.%: daemon-base.%
	@$(MAKE) -C $(STAGING_DIR)/daemon $(MAKECMDGOALS)

do.image.%: daemon.% ;

clean.image.%: do.image.%
	rm -rf $(STAGING_DIR)

stage: $(foreach p, $(FLAVORS_TO_BUILD), stage.$(p)) ;
build: $(foreach p, $(FLAVORS_TO_BUILD), stage.$(p) do.image.$(p))
clean: $(foreach p, $(FLAVORS_TO_BUILD), clean.image.$(p))
push:  $(foreach p, $(FLAVORS_TO_BUILD), do.image.$(p))

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
	@echo '    build        Build all images.'
	@echo '    clean        Clean all images.'
	@echo '    push         Push release images to registry.'
	@echo '    lint         Lint the source code.'
	@echo '    stage-test   Perform stageing integration test.'
