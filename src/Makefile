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
# Images to Build
#
# The images to build. The format is as follows:
# [ceph release name]@[arch]@[base os name]@[base os registry]@[base os repo]@[base os tag]
# e.g., luminous@amd64@ubuntu@_@ubuntu@16.04
#       luminous@arm64@ubuntu@arm64v8@ubuntu@16.04

#TODO: Staging should also stage the architecture, and the Dockerfile "FROM"
#      replacement should be done from the baseos_reg/baseos_repo:baseos_tag
#      rather than a __VARIABLE__ file.

FLAVORS_TO_BUILD ?= \
	luminous@amd64@ubuntu@_@ubuntu@16.04 \
	luminous@amd64@opensuse@_@opensuse@42.3 \

IMAGES_TO_BUILD := daemon-base daemon

REGISTRY ?= ceph

# ==============================================================================
# Targets
.PHONY: all build push clean stage

all: build

setvars.%:
	$(eval export CEPH_VERSION := $(word 1, $(subst @, ,$*)))
	$(eval export ARCH := $(word 2, $(subst @, ,$*)))
	$(eval export BASEOS_NAME := $(word 3, $(subst @, ,$*)))
	$(eval export BASEOS_REG := $(word 4, $(subst @, ,$*)))
	$(eval export BASEOS_REPO := $(word 5, $(subst @, ,$*)))
	$(eval export BASEOS_TAG := $(word 6, $(subst @, ,$*)))
	$(eval export IMAGES_TO_BUILD := $(IMAGES_TO_BUILD))
	$(eval export STAGING_DIR := staging-$(CEPH_VERSION)-$(BASEOS_NAME)-$(BASEOS_TAG)-$(ARCH))
	$(eval export BASE_IMAGE := $(BASEOS_REG)/$(BASEOS_REPO):$(BASEOS_TAG))
# Strip _/ from  beginning if exists
	$(eval export BASE_IMAGE := $(patsubst _/%,%,$(BASE_IMAGE)))
	$(eval export DAEMON_BASE_IMAGE := \
		$(REGISTRY)/daemon-base:$(CEPH_VERSION)-$(BASEOS_NAME)-$(BASEOS_TAG)-$(ARCH))
	$(eval export DAEMON_IMAGE := \
		$(REGISTRY)/daemon:$(CEPH_VERSION)-$(BASEOS_NAME)-$(BASEOS_TAG)-$(ARCH))
	@true

stage.%: setvars.%
	@sh -c ./stage.py

daemon-base.%: setvars.%
	@$(MAKE) -C $(STAGING_DIR)/daemon-base $(MAKECMDGOALS)

daemon.%: daemon-base.%
	@$(MAKE) -C $(STAGING_DIR)/daemon $(MAKECMDGOALS)

do.image.%: daemon.% ;

clean.image.%: daemon.%
	rm -rf $(STAGING_DIR)

stage: $(foreach p, $(FLAVORS_TO_BUILD), stage.$(p)) ;
build: $(foreach p, $(FLAVORS_TO_BUILD), stage.$(p) do.image.$(p)) ;
push: $(foreach p, $(FLAVORS_TO_BUILD), do.image.$(p)) ;
clean: $(foreach p, $(FLAVORS_TO_BUILD), clean.image.$(p))

# TODO: clean.all that also looks for all artifacts in their expected locations,
#       not just things part of FLAVORS_TO_BUILD

# ==============================================================================
# Help

.PHONY: help
help:
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Targets:'
	@echo '    build        Build all images.'
	@echo '    clean        Clean all images and staging dirs.'
	@echo '    push         Push all images.'
	@echo '    stage        Set up staging dirs for all images.'
