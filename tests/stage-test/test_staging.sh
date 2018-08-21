#!/usr/bin/env bash
set -euo pipefail

# Integration test to make sure staging is working properly

export CEPH_VERSION_SPEC=luminous-12.2.1-0
CEPH_VERSION=$(maint-lib/ceph_version.sh "${CEPH_VERSION_SPEC}" "CEPH_VERSION")
export CEPH_VERSION
CEPH_POINT_RELEASE=$(maint-lib/ceph_version.sh "${CEPH_VERSION_SPEC}" "CEPH_POINT_RELEASE")
export CEPH_POINT_RELEASE
export DISTRO=centos
export DISTRO_VERSION=7
export HOST_ARCH=x86_64
export BASEOS_REGISTRY=""
export BASEOS_REPO=centos.repo
export BASEOS_TAG=centos.tag
export STAGING_DIR=tests/stage-test/staging/${CEPH_VERSION}${CEPH_POINT_RELEASE}-${BASEOS_REPO}-${BASEOS_TAG}-${HOST_ARCH}
export IMAGES_TO_BUILD="daemon-base daemon"
export RELEASE='test-release'
export DAEMON_BASE_IMAGE=test-reg/daemon-base:test-release-1
export DAEMON_IMAGE=test-reg/daemon:test-release-1
export NESTED_ENV="__ENV_[CEPH_VERSION]__"
export NESTED_FILE="__H4X0R__"

run_stage=$(cat <<'EOF'
import sys
sys.path.append('maint-lib')
from stage import *
import stagelib.git as git

CORE_FILES_DIR = "tests/stage-test/src"
CEPH_RELEASES_DIR = "tests/stage-test/ceph-releases/"

def get_repo(): return 'testrepo'
git.get_repo = get_repo
def get_branch(): return 'testbranch'
git.get_branch = get_branch
def get_hash(): return 'testhash'
git.get_hash = get_hash
def file_is_dirty(file):
    return True if file == 'tests/stage-test/src/daemon/src-daemon-test-file' else False
git.file_is_dirty = file_is_dirty
def branch_is_dirty():
    return True
git.branch_is_dirty = branch_is_dirty

main(CORE_FILES_DIR, CEPH_RELEASES_DIR)
EOF
)

python3 -c "${run_stage}" | tee tests/stage-test/staging_output.txt
mv tests/stage-test/staging_output.txt "${STAGING_DIR}"

diff --brief -Nr --exclude 'find-src' --exclude '*.log' --exclude '*.bak' \
  tests/stage-test/stage-key/ "${STAGING_DIR}"

echo "STAGING TEST PASSED"
echo ""
