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

# remove default suffixes as we don't use them
.SUFFIXES:
SHELL := /bin/bash

# =====================================================================================
# Common Targets
#
.PHONY: all build push clean
all: build

# =====================================================================================
# Common Build Options

SED_CMD ?= sed -i -e

CACHEBUST ?= 0
ifeq ($(CACHEBUST),1)
BUILD_ARGS += --no-cache
endif

V ?= 0
ifeq ($(V),1)
MAKEFLAGS += VERBOSE=1
else
MAKEFLAGS += --no-print-directory
BUILD_ARGS ?= -q
endif

PULL ?= 1
ifeq ($(PULL),1)
BUILD_BASE_ARGS += --pull
endif
export PULL

BUILD_BASE_ARGS += $(BUILD_ARGS)

# =====================================================================================
# Set the host platform

HOST_OS := $(shell uname -s)
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
HOST_ARCH := amd64
else
$(error unsupported build platform)
endif
HOST_PLATFORM := $(HOST_OS)_$(HOST_ARCH)

# =====================================================================================
# Set the base OS image name

BASEOS_NAME ?= ubuntu
BASEOS_REG ?= _
BASEOS_REPO ?= ubuntu
BASEOS_TAG ?= 16.04

ifeq ($(BASEOS_REG),_)
BASEOS_IMAGE := $(BASEOS_REPO):$(BASEOS_TAG)
else
BASEOS_IMAGE := $(BASEOS_REG)/$(BASEOS_REPO):$(BASEOS_TAG)
endif
BASEOS_IMAGE_TAG := $(BASEOS_NAME)-$(BASEOS_TAG)

# =====================================================================================
# Docker Registry Options

REGISTRY ?= ceph

# =====================================================================================
# Ceph Release

CEPH_VERSION ?= luminous
ARCH ?= amd64

# =====================================================================================
# nukes all images ( for testing purposes only )
#
nuke:
	@for c in $$(docker ps -a -q --no-trunc); do \
		echo stopping and removing container $${c}; \
		docker stop $${c}; \
		docker rm $${c}; \
	done
	@for i in $$(docker images -q); do \
		echo removing image $$i; \
		docker rmi -f $$i > /dev/null 2>&1; \
	done
