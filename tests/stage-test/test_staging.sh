#!/usr/bin/env bash
set -euo pipefail

# Integration test to make sure staging is working properly

export CEPH_VERSION=luminous
export ARCH=x86_64
export OS_NAME=ubuntu
export OS_VERSION=16.04
export BASEOS_REG=_
export BASEOS_REPO=ubuntu
export BASEOS_TAG=16.04
export STAGING_DIR=tests/stage-test/staging/${CEPH_VERSION}-${BASEOS_REPO}-${BASEOS_TAG}-${ARCH}
export IMAGES_TO_BUILD="daemon-base daemon"
export RELEASE='test-release'
export DAEMON_BASE_IMAGE=test-reg/daemon-base:test-release-1
export DAEMON_IMAGE=test-reg/daemon:test-release-1

run_stage=$(cat <<'EOF'
import sys
sys.path.append('maint-lib')
from stage import *
import stagelib.git as git

CORE_FILES_DIR = "tests/stage-test/src"
CEPH_RELEASES_DIR = "tests/stage-test/ceph-releases/"
BLACKLIST_FILE = "tests/stage-test/flavor-blacklist.txt"

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

main(CORE_FILES_DIR, CEPH_RELEASES_DIR, BLACKLIST_FILE)
EOF
)
python3 -c "${run_stage}" | tee tests/stage-test/staging_output.txt
mv tests/stage-test/staging_output.txt ${STAGING_DIR}

diff --brief -Nr --exclude 'find-src' --exclude '*.log' --exclude '*.bak' \
     tests/stage-test/stage-key/ "${STAGING_DIR}"

echo "STAGING TEST PASSED"
echo ""
