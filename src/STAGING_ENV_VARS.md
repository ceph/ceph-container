# Useful environment variables that are set during staging
See `ceph-container/maint-lib/stagelib/envglobals.py` for most updated list and descriptions.

## Required as input to staging
 - CEPH_VERSION
 - HOST_ARCH
 - BASEOS_REG
 - BASEOS_REPO
 - BASEOS_TAG
 - IMAGES_TO_BUILD
 - STAGING_DIR
 - RELEASE
 - DAEMON_BASE_IMAGE
 - DAEMON_IMAGE

## Generated during staging
### Git tracking
 - GIT_REPO
 - GIT_BRANCH
 - GIT_COMMIT
 - GIT_CLEAN

### Architecture
 - GO_ARCH
