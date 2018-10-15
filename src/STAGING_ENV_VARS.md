# Useful environment variables that are set during staging
See `ceph-container/maint-lib/stagelib/envglobals.py` for most updated list and descriptions.

<!-- generated via cd ../maint-lib ; python3 -m stagelib.envglobals -->

## Required as input to staging

* CEPH_VERSION       Ceph named version part of the ceph-releases source path
                     (e.g., luminous, mimic)
* CEPH_POINT_RELEASE Points to specific version of Ceph (e.g -12.2.0) or empty
* DISTRO             Distro part of the ceph-releases source path (e.g., opensuse__leap, centos)
* DISTRO_VERSION     Distro version part of the ceph-releases source path
                     (e.g. in quotes, opensuse__leap/"42.3", centos/"7")
* HOST_ARCH          Architecture of binaries being built (e.g., amd64, arm32, arm64)
* BASEOS_REGISTRY    Registry for the container base image (e.g., _ (x86_64), arm64v8 (aarch64))
                     There is a relation between HOST_ARCH and this value
* BASEOS_REPO        Repository for the container base image (e.g., centos, opensuse__leap)
* BASEOS_TAG         Tagged version of BASEOS_REPO container (e.g., 7, 42.3 respectively)
* IMAGES_TO_BUILD    Container images to be built (usually should be "dockerfile daemon")
* STAGING_DIR        Dir into which files will be staged
                     This dir will be overwritten if it already exists
* RELEASE            Release string for the build
* DAEMON_BASE_IMAGE  Tag given to the daemon-base image and used as base for the daemon image
* DAEMON_IMAGE       Tag given to the daemon image

## Generated during staging

### Container image: BASE_IMAGE

Computed from BASEOS_REGISTRY, BASEOS_REPO and BASEOS_TAG. There is a special treatment to
support base images containing slashes: If BASEOS_REPO contains a double underscore, it's
being replaced with a slash in the resulting BASE_IMAGE. I.e. if BASEOS_REPO is set to
`opensuse__leap`, BASE_IMAGE will contain `opensuse/leap`.
    

### Git info

Export git-related environment variables to the current environment so they may be used later
for variable replacements.
Variables set:

- GIT_REPO - current repo
- GIT_COMMIT - current commit hash
- GIT_BRANCH - current branch
- GIT_CLEAN - "False" if there are uncommitted changes in branch, "True" otherwise
 
### Architecture:

Export the environment variable 'GO_ARCH' with the golang architecture equivalent to the
current Ceph arch. E.g., Ceph arch 'x86_64' equates to golang arch 'amd64'.
