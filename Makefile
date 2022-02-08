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
FLAVORS ?= \
	octopus,centos,8 \
	pacific,centos,8 \
	quincy,centos,8 \
	master,centos,8

TAG_REGISTRY ?= ceph

# By default the RELEASE version is the git branch name
# Could be overrided by user at build time
RELEASE ?= $(shell git rev-parse --abbrev-ref HEAD)

DAEMON_BASE_TAG ?= ""
DAEMON_TAG ?= ""

# These values are given sane defaults if they are unset. Otherwise, they get the value specified.
BASEOS_REGISTRY ?= ""
BASEOS_REPO ?= ""
BASEOS_TAG ?= ""

# Use Ceph development build packages from shaman/chacra repositories.
CEPH_DEVEL ?= false
OSD_FLAVOR ?= "default"


# ==============================================================================
# Internal definitions
include maint-lib/makelib.mk

# All flavor options that can be passed to FLAVORS
ALL_BUILDABLE_FLAVORS := \
	octopus,centos,7 \
	octopus,centos,8 \
	pacific,centos,8 \
	quincy,centos,8 \
	master,centos,8

# ==============================================================================
# Build targets
.PHONY: all stage build build.parallel build.all push push.parallel push.all

stage.%:
	@$(call set_env_vars,$*) sh -c maint-lib/stage.py

# Make daemon-base.% and/or daemon.% target based on IMAGES_TO_BUILD setting
#do.image.%: | stage.% $(foreach i, $(IMAGES_TO_BUILD), $(i).% ) ;
do.image.%: stage.%
	$(foreach i, $(IMAGES_TO_BUILD), \
		$(call set_env_vars,$*); $(MAKE) $(call set_env_vars,$*) -C $$STAGING_DIR/$(i) \
			$(call set_env_vars,$*) $(MAKECMDGOALS)$(\n))

stage: $(foreach p, $(FLAVORS), stage.$(HOST_ARCH),$(p)) ;
build: $(foreach p, $(FLAVORS), do.image.$(HOST_ARCH),$(p)) ;
push:  $(foreach p, $(FLAVORS), do.image.$(HOST_ARCH),$(p)) ;

push.parallel:
	@$(MAKE) $(PARALLEL) push

push.all:
	@$(MAKE) FLAVORS="$(ALL_BUILDABLE_FLAVORS)" push.parallel

build.parallel:
	@$(MAKE) $(PARALLEL) build

build.all:
	@$(MAKE) FLAVORS="$(ALL_BUILDABLE_FLAVORS)" build.parallel


# ==============================================================================
# Clean targets
.PHONY: clean clean.nones clean.all

clean.image.%: do.image.%
	@$(call set_env_vars); rm -rf $$STAGING_DIR

clean: $(foreach p, $(FLAVORS), clean.image.$(HOST_ARCH),$(p))

clean.nones:
	@if [ -n "$(shell docker images --quiet --filter "dangling=true")" ] ; then \
		docker rmi -f $(shell docker images --quiet --filter "dangling=true") || true ; \
	fi

clean.all: clean.nones
	@rm -rf staging/
	@# Inspect each image, and if we find 'CEPH_POINT_RELEASE' we can be pretty sure it's a
	@# ceph-container image and safe to delete
	@for image in $(shell docker images --quiet); do \
		if docker inspect "$$image" | grep -q 'CEPH_POINT_RELEASE'; then \
			docker rmi -f "$$image" || true ; \
		fi ; \
	done


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

# Aligned to 100 chars
define HELPTEXT

Usage: make [OPTIONS] ... <TARGETS>

TARGETS:

  Building:
    stage             Form staging dirs for all images. Dirs are reformed if they exist.
    build             Build all images. Staging dirs are reformed if they exist.
    build.parallel    Build default flavors in parallel.
    build.all         Build all buildable flavors with build.parallel
    push              Push release images to registry.
    push.parallel     Push release images to registy in parallel

  Clean:
    clean             Remove images and staging dirs for the current flavors.
    clean.nones       Remove all image artifacts tagged <none>.
    clean.all         Remove all images and all staging dirs. Implies "clean.nones".
                      WARNING: Could be unsafe. Deletes all images w/ the text
                               "CEPH_POINT_RELEASE" anywhere in the container metadata.

  Testing:
    lint              Lint the source code.
    test.staging      Perform staging integration test.

  Help:
    help              Print this help message.
    show.flavors      Show all flavor options to FLAVORS.
    flavors.modified  Show the flavors impacted by this branch's changes vs origin/master.
                      All buildable flavors are staged for this test.
                      The env var VS_BRANCH can be set to compare vs a different branch.

OPTIONS:

  FLAVORS - ceph-container images to operate on in the form below:
              <CEPH_VERSION>[CEPH_POINT_RELEASE],<DISTRO>,<DISTRO_VERSION>
            Multiple forms can be separated by spaces.
      CEPH_VERSION - Ceph version name part of the ceph-releases source path (e.g., luminous, mimic)
      CEPH_POINT_RELEASE - Optional field to select a particular version of Ceph
                           Regarding the package manager the version separator may vary:
                             yum/dnf/zypper are using dash (e.g -12.2.2)
                             apt is using an equal (e.g =12.2.2)
      DISTRO - Distro part of the ceph-releases source path (e.g., opensuse, centos)
      DISTRO_VERSION - Distro version part of the ceph-releases source path
                       (e.g., opensuse/"42.3", centos/"7")
    e.g., make FLAVORS="luminous,opensuse,42.3" ...

	It is also possible to build a container running the latest development release (master).
	This is only available on centos with the following command :
		make FLAVORS="master,centos,7"

  RELEASE - The release version to integrate in the tag. If omitted, set to the branch name.

  CEPH_DEVEL - Use the ceph development packages from shaman/chacra instead of stable (default false).

ADVANCED OPTIONS:
    It is advised only to use the below options for builds of a single flavor. These options are
    global overrides that affect builds of all target flavors.

  TAG_REGISTRY - Registry name to tag images with and to push images to.  Default: "ceph"
                 If specified as empty string, no registry will be prepended to the tag.
                 e.g., TAG_REGISTRY="myreg" tags images "myreg/daemon{,-base}" & pushes to "myreg".

  DAEMON_BASE_TAG - Override the tag name for the daemon-base image.
  DAEMON_TAG      - Override the tag name for the daemon image.
    For tags above, the final image tag will include the registry defined by "TAG_REGISTRY".
    e.g., TAG_REGISTRY="myreg" DAEMON_TAG="mydaemontag" will tag daemon "myreg/mydaemontag"

  BASEOS_REGISTRY - Registry part of the build's base image.  Default: none (empty)
  BASEOS_REPO     - Repo part of the build's base image.  Default: value from DISTRO
  BASEOS_TAG      - Tag part of the build's base image.  Default: value from DISTRO_VERSION
    e.g., BASEOS_REPO=debian BASEOS_TAG=jessie will use "debian:jessie" as a base image
          BASEOS_REGISTRY with above will use "myreg/debian:jessie" as a base image

  IMAGES_TO_BUILD - Change which images to build. Primarily useful for building daemon-base only,
                    but could be used to rebuild the daemon for local dev when base hasn't changed.
                    Default: "daemon-base daemon". Do NOT list specify images out of order!
                    e.g., IMAGES_TO_BUILD=daemon-base or IMAGES_TO_BUILD=daemon

endef
export HELPTEXT
help:
	@echo "$$HELPTEXT"

show.flavors:
	@echo $(ALL_BUILDABLE_FLAVORS)

flavors.modified:
	@ALL_BUILDABLE_FLAVORS="$(ALL_BUILDABLE_FLAVORS)" maint-lib/flavors-modified-vs-master.py
