# Container images built for each flavor
IMAGES_TO_BUILD := daemon-base daemon

# Given a variable name $(1) and a build flavor $(2), print a string
#   <variable name>="<variable value>". When used in a target, this will effectively set the
#   environment variable <variable name> to the appropriate value.
comma := ,
define set_env_var
$(shell set -eu ; \
	CEPH_VERSION=$(word 1, $(subst $(comma), ,$(2))) ; \
	ARCH=$(word 2, $(subst $(comma), ,$(2))) ; \
	OS_NAME=$(word 3, $(subst $(comma), ,$(2))) ; \
	OS_VERSION=$(word 4, $(subst $(comma), ,$(2))) ; \
	BASEOS_REG=$(word 5, $(subst $(comma), ,$(2))) ; \
	BASEOS_REPO=$(word 6, $(subst $(comma), ,$(2))) ; \
	BASEOS_TAG=$(word 7, $(subst $(comma), ,$(2))) ; \
	IMAGES_TO_BUILD='$(IMAGES_TO_BUILD)' ; \
	STAGING_DIR=staging/$$CEPH_VERSION-$$BASEOS_REPO-$$BASEOS_TAG-$$ARCH ; \
	BASE_IMAGE=$$BASEOS_REG/$$BASEOS_REPO:$$BASEOS_TAG ; \
	BASE_IMAGE=$${BASE_IMAGE#_/} ; \
	DAEMON_BASE_IMAGE=$(REGISTRY)/daemon-base:$$CEPH_VERSION-$$BASEOS_REPO-$$BASEOS_TAG-$$ARCH ; \
	DAEMON_IMAGE=$(REGISTRY)/daemon:$$CEPH_VERSION-$$BASEOS_REPO-$$BASEOS_TAG-$$ARCH ; \
	TIMESTAMP=$(TIMESTAMP); \
	RELEASE=$(RELEASE); \
	echo "$(1)=\"$$$(1)\""
)
endef
