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
# CEPH_VERSION,BASEOS_REPO,BASEOS_TAG
FLAVORS ?= \
	luminous,ubuntu,16.04 \
	jewel,ubuntu,16.04 \
	jewel,ubuntu,14.04 \
	kraken,ubuntu,16.04 \
	luminous,centos,7 \
	jewel,centos,7 \
	kraken,centos,7 \

REGISTRY ?= ceph

# By default the RELEASE version is the git branch name
# Could be overrided by user at build time
RELEASE ?= $(shell git rev-parse --abbrev-ref HEAD)

DAEMON_BASE_TAG ?= ""
DAEMON_TAG ?= ""

BASE_IMAGE ?= ""


# ==============================================================================
# Internal definitions
include maint-lib/makelib.mk

# All flavor options that can be passed to FLAVORS
# CEPH_VERSION,BASEOS_REPO,BASEOS_TAG
ALL_BUILDABLE_FLAVORS := \
	luminous,ubuntu,16.04 \
	jewel,ubuntu,16.04 \
	jewel,ubuntu,14.04 \
	kraken,ubuntu,16.04 \
	luminous,centos,7 \
	jewel,centos,7 \
	kraken,centos,7 \
	luminous,opensuse,42.3 \

# ==============================================================================
# Build targets
.PHONY: all stage build build.parallel build.all push

stage.%:
	@$(call set_env_vars,$*) sh -c maint-lib/stage.py

daemon-base.%: stage.%
	@$(call set_env_vars,$*); $(MAKE) -C $$STAGING_DIR/daemon-base \
	  $(call set_env_vars,$*) $(MAKECMDGOALS)

daemon.%: daemon-base.%
	@$(call set_env_vars,$*); $(MAKE) $(call set_env_vars,$*) -C $$STAGING_DIR/daemon \
	  $(call set_env_vars,$*) $(MAKECMDGOALS)

do.image.%: daemon.% ;

stage: $(foreach p, $(FLAVORS), stage.$(HOST_ARCH),$(p)) ;
build: $(foreach p, $(FLAVORS), do.image.$(HOST_ARCH),$(p)) ;
push:  $(foreach p, $(FLAVORS), do.image.$(HOST_ARCH),$(p)) ;

push.parallel:
	@$(MAKE) $(PARALLEL) push

build.parallel:
	@$(MAKE) $(PARALLEL) build

build.all:
	@$(MAKE) FLAVORS="$(ALL_BUILDABLE_FLAVORS)" build.parallel


# ==============================================================================
# Clean targets
.PHONY: clean clean.nones clean.all clean.nuke

clean.image.%: do.image.%
	@$(call set_env_vars); rm -rf $$STAGING_DIR

clean: $(foreach p, $(FLAVORS), clean.image.$(HOST_ARCH),$(p))

clean.nones:
	@docker rmi -f $(shell docker images | egrep "^<none> " | awk '{print $$3}' | uniq) || true

clean.all: clean.nones
	@rm -rf staging/
	# Don't mess with other registries for some semblance of a safe clean.
	@docker rmi -f \
		$(shell docker images | egrep "^$(REGISTRY)/daemon(-base)? " | \
		  awk '{print $$3}' | uniq) || true

clean.nuke: clean.all
	@docker rmi -f \
		$(shell docker images | egrep "^.*/daemon(-base)? " | awk '{print $$3}' | uniq) || true


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
	@echo '    <CEPH_VERSION>[CEPH_POINT_RELEASE],<BASEOS_REPO>,<BASEOS_TAG>'
	@echo '    and multiple forms may be separated by spaces.'
	@echo '      CEPH_VERSION - named ceph version (e.g., luminous, mimic)'
	@echo '      CEPH_POINT_RELEASE - Optional field to select a particular version of Ceph'
	@echo '                           Regarding the package manager the version separator may vary :'
	@echo '                             yum/dnf/zypper are using dash (e.g -12.2.2)'
	@echo '                             apt is using an equal (e.g =12.2.2)'
	@echo '      BASEOS_REPO  - The base image to use for the daemon-base container. This is also'
	@echo '                      the distro path sourced from ceph-container (e.g., ubuntu, centos)'
	@echo '      BASEOS_TAG   - Tagged version of the base repo to use. Also the distro version'
	@echo '                      sourced from ceph-container (e.g., ubuntu:"16.04", centos:"7")'
	@echo '    e.g., FLAVORS="luminous,ubuntu,16.04 jewel,ubuntu,14.04"'
	@echo ''
	@echo '  REGISTRY - The name of the registry to tag images with and to push images to.'
	@echo '             Defaults to "ceph".'
	@echo '             If specified as empty string, no registry will be prepended to the tag.'
	@echo '    e.g., REGISTRY="myreg" will tag images "myreg/daemon{,-base}" and push to "myreg".'
	@echo ''
	@echo '  RELEASE - The release version to integrate in the tag. If omitted, set to the branch name.'
	@echo ''
	@echo '  DAEMON_BASE_TAG - Override the tag name for the daemon-base image'
	@echo '  DAEMON_TAG - Override the tag name for the daemon image'
	@echo '    For tags above, the final image tag will include the registry defined by "REGISTRY".'
	@echo '    e.g., REGISTRY="myreg" DAEMON_TAG="mydaemontag" will tag the daemon "myreg/mydaemontag"'
	@echo ''
	@echo '  BASE_IMAGE - Do not compute the base image to be used as container base from BASEOS_REPO'
	@echo '               and BASEOS_TAG. Instead, use the base image specified. The BASEOS_ vars will'
	@echo '               still be used to determine the ceph-container source files to use.'
	@echo '               e.g., BASE_IMAGE="myrepo/mycustomubuntu:mytag"'
	@echo ''

show.flavors:
	@echo $(ALL_BUILDABLE_FLAVORS)

flavors.modified:
	@ALL_BUILDABLE_FLAVORS="$(ALL_BUILDABLE_FLAVORS)" maint-lib/flavors-modified-vs-master.py
