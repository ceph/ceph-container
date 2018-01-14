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

IMAGE = $(REGISTRY)/base:$(ARCH)-$(BASEOS_IMAGE_TAG)
ROOTFS_BUILDER_IMAGE := $(REGISTRY)/rootfs-builder:$(ARCH)-$(BASEOS_IMAGE_TAG)
ROOTFS_IMAGE := $(REGISTRY)/rootfs:$$(docker images -q $(ROOTFS_BUILDER_IMAGE))

# Start with the full os-base image, minimize it by cleaning uneeded
# files and then export the image into a tarball and back in into
# a new "slim" image. This is the only way to get the removed files
# from the image history.
# Note docker multi-stage builds make this much easier but are only
# available in docker 17.03 which is not widely available.
BUILDER_TEMP := $(shell mktemp -d)
rootfs-builder:
	@echo === docker build $(ROOTFS_BUILDER_IMAGE)
	@cp Dockerfile.rootfs-$(BASEOS_NAME) $(BUILDER_TEMP)/Dockerfile
	@cd $(BUILDER_TEMP) && $(SED_CMD) 's|BASEIMAGE|$(BASEOS_IMAGE)|g' Dockerfile
	@docker build $(BUILD_BASE_ARGS) -t $(ROOTFS_BUILDER_IMAGE) $(BUILDER_TEMP)
	@if [ -z "$$(docker images -q $(ROOTFS_IMAGE))" ]; then \
		$(MAKE) rootfs; \
	fi
	@rm -fr $(BUILDER_TEMP)

rootfs:
	@echo === docker build $(ROOTFS_IMAGE)
	@CID=`docker create $(ROOTFS_BUILDER_IMAGE) /bin/bash` &&\
	  docker export $$CID > $(BUILDER_TEMP)/rootfs.tar &&\
	  docker rm -f $$CID
	@cp Dockerfile.rootfs $(BUILDER_TEMP)/Dockerfile
	@docker build $(BUILD_ARGS) -t $(ROOTFS_IMAGE) $(BUILDER_TEMP)

TEMP := $(shell mktemp -d)
build: rootfs-builder
	@echo === docker build $(IMAGE)
	@cp Dockerfile $(TEMP)
	@cd $(TEMP) && $(SED_CMD) "s|BASEIMAGE|$(ROOTFS_IMAGE)|g" Dockerfile
	@docker build $(BUILD_ARGS) -t $(IMAGE) $(TEMP)
	@rm -fr $(TEMP)

push: ; @:
clean: ; @docker rmi $(IMAGE) $(ROOTFS_BUILDER_IMAGE) $(ROOTFS_IMAGE)
