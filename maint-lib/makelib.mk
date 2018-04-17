# Container images built for each flavor
IMAGES_TO_BUILD := daemon-base daemon

HOST_ARCH ?= $(shell uname --machine)


# Export all relevant environment variables from a flavor spec in the format:
#   HOST_ARCH,CEPH_VERSION_SPEC,BASEOS_REPO,BASEOS_TAG
# Note that CEPH_VERSION_SPEC is split into CEPH_VERSION and CEPH_POINT_RELEASE
# Note that this format is the same as the FLAVORS spec format with HOST_ARCH prepended; it's
#   necessary to pass HOST_ARCH in so we can do parallel cross-builds of different arches later.
comma := ,
define set_env_vars
$(shell bash -c 'set -eu ; \
	function set_var () { export $$1="$$2" ; echo -n $$1="\"$$2\" " ; } ; \
	set_var HOST_ARCH          "$(word 1, $(subst $(comma), ,$(1)))" ; \
	ceph_version_spec="$(word 2, $(subst $(comma), ,$(1)))" ; \
	set_var CEPH_VERSION       "$$(bash maint-lib/ceph_version.sh "$$ceph_version_spec" CEPH_VERSION)" ; \
	set_var CEPH_POINT_RELEASE "$$(bash maint-lib/ceph_version.sh "$$ceph_version_spec" CEPH_POINT_RELEASE)" ; \
	set_var BASEOS_REPO        "$(word 3, $(subst $(comma), , $(1)))" ; \
	set_var BASEOS_TAG         "$(word 4, $(subst $(comma), , $(1)))" ; \
	set_var BASEOS_REGISTRY    "$(BASEOS_REGISTRY)" ; \
	set_var IMAGES_TO_BUILD    "$(IMAGES_TO_BUILD)" ; \

	set_var STAGING_DIR       "staging/$$CEPH_VERSION$$CEPH_POINT_RELEASE-$$BASEOS_REPO-$$BASEOS_TAG-$$HOST_ARCH" ; \
	base_img="$$BASEOS_REPO:$$BASEOS_TAG" ; \
	if [ -n "$(BASE_IMAGE)" ] ; then base_img="$(BASE_IMAGE)" ; fi ; \
	set_var BASE_IMAGE        "$${base_img#_/}" ; \
	set_var RELEASE           "$(RELEASE)" ; \
	\
	daemon_base_img="daemon-base:$(RELEASE)-$$CEPH_VERSION-$$BASEOS_REPO-$$BASEOS_TAG-$$HOST_ARCH" ; \
	if [ -n "$(DAEMON_BASE_TAG)" ] ; then daemon_base_img="$(DAEMON_BASE_TAG)" ; fi ; \
	if [ -n "$(TAG_REGISTRY)" ]; then daemon_base_img="$(TAG_REGISTRY)/$$daemon_base_img" ; fi ; \
	set_var DAEMON_BASE_IMAGE "$$daemon_base_img" ; \
	\
	daemon_img="daemon:$(RELEASE)-$$CEPH_VERSION-$$BASEOS_REPO-$$BASEOS_TAG-$$HOST_ARCH" ; \
	if [ -n "$(DAEMON_TAG)" ] ; then daemon_img="$(DAEMON_TAG)" ; fi ; \
	if [ -n "$(TAG_REGISTRY)" ]; then daemon_img="$(TAG_REGISTRY)/$$daemon_img" ; fi ; \
	set_var DAEMON_IMAGE      "$$daemon_img" ; \
	'
)
endef


# Make supports output-sync flag for parallel builds starting in version 4.
# Use $(PARALLEL) to set options to make to do a parallel build with output-sync if possible.
ifeq (4.00,$(firstword $(sort $(MAKE_VERSION) 4.00)))
PARALLEL := --jobs $(nproc) --output-sync
else
PARALLEL := --jobs $(nproc)
endif
