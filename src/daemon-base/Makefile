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

include ../image.mk

IMAGE := $(REGISTRY)/daemon-base:$(CEPH_VERSION)-$(ARCH)-$(BASEOS_IMAGE_TAG)
BASEIMAGE = $(REGISTRY)/base:$(ARCH)-$(BASEOS_IMAGE_TAG)
TEMP := $(shell mktemp -d)

build:
	@echo === docker build $(IMAGE)
	@cp -a . $(TEMP)
	@cp Dockerfile.$(CEPH_VERSION)-$(BASEOS_NAME) $(TEMP)/Dockerfile
	@cd $(TEMP) && $(SED_CMD) 's|BASEIMAGE|$(BASEIMAGE)|g' Dockerfile
	@docker build $(BUILD_ARGS) -t $(IMAGE) $(TEMP)
	@rm -fr $(TEMP)

push: ; @docker push $(IMAGE)
clean: ; @docker rmi $(IMAGE)
