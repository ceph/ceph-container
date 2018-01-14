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

include image.mk

# ====================================================================================
# Images to Build
#
# The images to build. The format is as follows:
# [ceph release name]_[arch]_[base os name]_[base os registry]_[base os repo]_[base os tag]

IMAGES_TO_BUILD ?= \
	luminous@amd64@ubuntu@_@ubuntu@16.04 \
	luminous@arm64@ubuntu@arm64v8@ubuntu@16.04

# ====================================================================================
# Targets

base.%:
	@$(MAKE) -C base $(MAKECMDGOALS) ARCH=$(word 2, $(subst @, ,$*)) BASEOS_NAME=$(word 3, $(subst @, ,$*)) BASEOS_REG=$(word 4, $(subst @, ,$*)) BASEOS_REPO=$(word 5, $(subst @, ,$*)) BASEOS_TAG=$(word 6, $(subst @, ,$*))

daemon-base.%: base.%
	@$(MAKE) -C daemon-base $(MAKECMDGOALS) CEPH_VERSION=$(word 1, $(subst @, ,$*)) ARCH=$(word 2, $(subst @, ,$*)) BASEOS_NAME=$(word 3, $(subst @, ,$*)) BASEOS_REG=$(word 4, $(subst @, ,$*)) BASEOS_REPO=$(word 5, $(subst @, ,$*)) BASEOS_TAG=$(word 6, $(subst @, ,$*))

daemon.%: daemon-base.%
	@$(MAKE) -C daemon $(MAKECMDGOALS) CEPH_VERSION=$(word 1, $(subst @, ,$*)) ARCH=$(word 2, $(subst @, ,$*)) BASEOS_NAME=$(word 3, $(subst @, ,$*)) BASEOS_REG=$(word 4, $(subst @, ,$*)) BASEOS_REPO=$(word 5, $(subst @, ,$*)) BASEOS_TAG=$(word 6, $(subst @, ,$*))

do.image.%: daemon.% ;
build: $(foreach p,$(IMAGES_TO_BUILD), do.image.$(p)) ;
clean: $(foreach p,$(IMAGES_TO_BUILD), do.image.$(p)) ;
push: $(foreach p,$(IMAGES_TO_BUILD), do.image.$(p)) ;

# ====================================================================================
# Help

.PHONY: help
help:
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Targets:'
	@echo '    build        Build all images.'
	@echo '    clean        Clean all images.'
	@echo '    push         Push release images to registry.'
	@echo ''
	@echo 'Options:'
	@echo '    CACHEBUST    Whether to disable image caching. Default is 0.'
	@echo '    PULL         Whether to pull base images. Default is 1.'
	@echo '    V            Set to 1 enable verbose build. Default is 0.'
