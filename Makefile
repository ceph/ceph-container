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

# When updating these defaults, be sure to check that ALL_BUILDABLE_FLAVORS is updated
# CEPH_VERSION,ARCH,OS_NAME,OS_VERSION,BASEOS_REG,BASEOS_REPO,BASEOS_TAG
FLAVORS ?= \
	luminous,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	jewel,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	jewel,x86_64,ubuntu,14.04,_,ubuntu,14.04 \
	kraken,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	luminous,x86_64,centos,7,_,centos,7 \
	jewel,x86_64,centos,7,_,centos,7 \
	kraken,x86_64,centos,7,_,centos,7 \

REGISTRY ?= ceph

# By default the RELEASE version is the git branch name
# Could be overrided by user at build time
RELEASE ?= $(shell git rev-parse --abbrev-ref HEAD)


# ==============================================================================
# Internal definitions
include maint-lib/makelib.mk

# All flavor options that can be passed to FLAVORS
# CEPH_VERSION,ARCH,OS_NAME,OS_VERSION,BASEOS_REG,BASEOS_REPO,BASEOS_TAG
ALL_BUILDABLE_FLAVORS := \
	luminous,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	jewel,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	jewel,x86_64,ubuntu,14.04,_,ubuntu,14.04 \
	kraken,x86_64,ubuntu,16.04,_,ubuntu,16.04 \
	luminous,x86_64,centos,7,_,centos,7 \
	jewel,x86_64,centos,7,_,centos,7 \
	kraken,x86_64,centos,7,_,centos,7 \

# ==============================================================================
# Build targets
.PHONY: all stage build build.parallel build.all push

stage.%:
	@$(call set_env_var,CEPH_VERSION,$*) $(call set_env_var,ARCH,$*) \
	$(call set_env_var,OS_NAME,$*) $(call set_env_var,OS_VERSION,$*) \
	$(call set_env_var,BASEOS_REG,$*) $(call set_env_var,BASEOS_REPO,$*) \
	$(call set_env_var,BASEOS_TAG,$*) $(call set_env_var,IMAGES_TO_BUILD,$*) \
	$(call set_env_var,STAGING_DIR,$*) $(call set_env_var,BASE_IMAGE,$*) \
	$(call set_env_var,DAEMON_BASE_IMAGE,$*) $(call set_env_var,DAEMON_IMAGE,$*) \
	$(call set_env_var,RELEASE,$*) \
	sh -c maint-lib/stage.py

daemon-base.%: stage.%
	@$(call set_env_var,STAGING_DIR,$*) ; $(MAKE) -C $$STAGING_DIR/daemon-base $(MAKECMDGOALS) \
	$(call set_env_var,DAEMON_BASE_IMAGE,$*)

daemon.%: daemon-base.%
	@$(call set_env_var,STAGING_DIR,$*) ; $(MAKE) -C $$STAGING_DIR/daemon $(MAKECMDGOALS) \
	$(call set_env_var,DAEMON_IMAGE,$*)

do.image.%: daemon.% ;

stage: $(foreach p, $(FLAVORS), stage.$(p)) ;
build: $(foreach p, $(FLAVORS), do.image.$(p)) ;
push:  $(foreach p, $(FLAVORS), do.image.$(p)) ;

push.parallel:
# Due to output-sync, will not output results until finished so there is no text interleaving
ifeq (4.00,$(firstword $(sort $(MAKE_VERSION) 4.00)))
	@$(MAKE) --jobs $(nproc) --output-sync push
else
	@$(MAKE) --jobs $(nproc) push
endif

build.parallel:
# Due to output-sync, will not output results until finished so there is no text interleaving
ifeq (4.00,$(firstword $(sort $(MAKE_VERSION) 4.00)))
	@$(MAKE) --jobs $(nproc) --output-sync build
else
	@$(MAKE) --jobs $(nproc) build
endif

build.all:
	@$(MAKE) FLAVORS="$(ALL_BUILDABLE_FLAVORS)" build.parallel


# ==============================================================================
# Clean targets
.PHONY: clean clean.nones clean.all clean.nuke

clean.image.%: do.image.%
	@$(call set_env_var,STAGING_DIR,$*); rm -rf $$STAGING_DIR

clean: $(foreach p, $(FLAVORS), clean.image.$(p))

clean.nones:
	@docker rmi -f $(shell docker images | egrep "^<none> " | awk '{print $$3}') || true

clean.all: clean.nones
	@rm -rf staging/
	# Don't mess with other registries for some semblance of a safe nuke.
	@docker rmi -f \
		$(shell docker images | egrep "^$(REGISTRY)/daemon(-base)? " | awk '{print $$3}') || true

clean.nuke: clean.all
	@docker rmi -f \
		$(shell docker images | egrep "^.*/daemon(-base)? " | awk '{print $$3}') || true


# ==============================================================================
# Test targets
.PHONY: lint test.staging

lint:
	flake8

test.staging:
	DEBUG=1 tests/stage-test/test_staging.sh

# ==============================================================================
# Help
.PHONY: help show.flavors flavors.modified

help:
	@echo ''
	@echo 'Usage: make [OPTIONS] ... <TARGETS>'
	@echo ''
	@echo 'TARGETS:'
	@echo ''
	@echo '  Building:'
	@echo '    stage             Form staging dirs for all images. Dirs are reformed if they exist.'
	@echo '    build             Build all images. Staging dirs are reformed if they exist.'
	@echo '    build.parallel    Build default flavors in parallel.'
	@echo '    build.all         Build all buildable flavors with build.parallel'
	@echo '    push              Push release images to registry.'
	@echo '    push.parallel     Push release images to registy in parallel'
	@echo ''
	@echo '  Clean:'
	@echo '    clean             Remove images and staging dirs for the current flavors.'
	@echo '    clean.nones       Remove all image artifacts tagged <none>.'
	@echo '    clean.all         Remove all images and all staging dirs. Implies "clean.nones".'
	@echo '                      Will only delete images in the specified REGISTRY for safety.'
	@echo '    clean.nuke        Same as "clean.all" but will not be limited to specified REGISTRY.'
	@echo '                      USE AT YOUR OWN RISK! This may remove non-project images.'
	@echo ''
	@echo '  Testing:'
	@echo '    lint              Lint the source code.'
	@echo '    test.staging      Perform stageing integration test.'
	@echo ''
	@echo '  Help:'
	@echo '    help              Print this help message.'
	@echo '    show.flavors      Show all flavor options to FLAVORS.'
	@echo "    flavors.modified  Show the flavors impacted by this branch's changes vs origin/master."
	@echo '                      All buildable flavors are staged for this test.'
	@echo '                      The env var VS_BRANCH can be set to compare vs a different branch.'
	@echo ''
	@echo 'OPTIONS:'
	@echo ''
	@echo '  FLAVORS - ceph-container images to operate on in the form'
	@echo '    <ceph rel>,<arch>,<os name>,<os version>,<base registry>,<base repo>,<base tag>'
	@echo '    and multiple forms may be separated by spaces.'
	@echo '      ceph rel - named ceph version (e.g., luminous, mimic)'
	@echo '      arch - architecture of Ceph packages used (e.g., x86_64, aarch64)'
	@echo '      os name - directory name for the os used by ceph-container (e.g., ubuntu)'
	@echo '      os version - directory name for the os version used by ceph-container (e.g., 16.04)'
	@echo '      base registry - registry to get base image from (e.g., "_" ~ x86_64, "arm64v8" ~ aarch64)'
	@echo '      base repo - The base image to use for the daemon-base container. generally this is'
	@echo '                  also the os name (e.g., ubuntu) but could be something like "alpine"'
	@echo '      base tag - Tagged version of the base os to use (e.g., ubuntu:"16.04", alpine:"3.6")'
	@echo '    e.g., FLAVORS_TO_BUILD="luminous,x86_64,ubuntu,16.04,_,ubuntu,16.04 \'
	@echo '                            luminous,aarch64,ubuntu,16.04,arm64v8,alpine,3.6"'
	@echo ''
	@echo '  REGISTRY - The name of the registry to tag images with and to push images to.'
	@echo '             Defaults to "ceph".'
	@echo '    e.g., REGISTRY="myreg" will tag images "myreg/daemon{,-base}" and push to "myreg".'
	@echo ''
	@echo '  RELEASE - The release version to integrate in the tag. If omitted, set to the branch name.'
	@echo ''

show.flavors:
	@echo $(ALL_BUILDABLE_FLAVORS)

flavors.modified:
	@ALL_BUILDABLE_FLAVORS="$(ALL_BUILDABLE_FLAVORS)" maint-lib/flavors-modified-vs-master.py
