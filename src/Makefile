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

IMAGES_TO_BUILD ?= \
	luminous@amd64@ubuntu@_@ubuntu@16.04 \
	luminous@amd64@opensuse@_@openuse@42.3 \

export REGISTRY ?= ceph

# ==============================================================================
# Targets
.PHONY: all build push clean stage

all: build

setvars.%:
	$(eval ceph_version := $(word 1, $(subst @, ,$*)))
	$(eval arch := $(word 2, $(subst @, ,$*)))
	$(eval baseos_name := $(word 3, $(subst @, ,$*)))
	$(eval baseos_reg := $(word 4, $(subst @, ,$*)))
	$(eval baseos_repo := $(word 5, $(subst @, ,$*)))
	$(eval baseos_tag := $(word 6, $(subst @, ,$*)))
	$(eval staging_dir := staging-$(ceph_version)-$(baseos_name)-$(baseos_tag))
	@true

stage.%: setvars.%
	sh stage.sh $(ceph_version) $(baseos_name) $(baseos_tag)

daemon.%: setvars.%
	@$(MAKE) -C $(staging_dir)/daemon $(MAKECMDGOALS) \
		CEPH_VERSION=$(ceph_version) ARCH=$(arch) \
		BASEOS_NAME=$(baseos_name) BASEOS_REG=$(baseos_reg) \
		BASEOS_REPO=$(baseos_repo) BASEOS_TAG=$(baseos_tag)

do.image.%: daemon.% ;

clean.image.%: daemon.%
	rm -rf $(staging_dir)

stage: $(foreach p, $(IMAGES_TO_BUILD), stage.$(p)) ;
build: $(foreach p, $(IMAGES_TO_BUILD), stage.$(p) do.image.$(p)) ;
push: $(foreach p, $(IMAGES_TO_BUILD), do.image.$(p)) ;
clean: $(foreach p, $(IMAGES_TO_BUILD), clean.image.$(p))

# TODO: clean.all that also looks for all artifacts in their expected locations,
#       not just things part of IMAGES_TO_BUILD

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
