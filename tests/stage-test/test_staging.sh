#!/usr/bin/env bash
set -euo pipefail

# Integration test to make sure staging is working properly

export CEPH_VERSION=luminous
export ARCH=amd64
export OS_NAME=ubuntu
export OS_VERSION=16.04
export BASEOS_REG=_
export BASEOS_REPO=ubuntu
export BASEOS_TAG=16.04
export STAGING_DIR=tests/stage-test/staging/${CEPH_VERSION}-${BASEOS_REPO}-${BASEOS_TAG}-${ARCH}
export IMAGES_TO_BUILD="daemon-base daemon"

run_stage=$(cat <<'EOF'
from stage import *
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

main(CORE_FILES_DIR, CEPH_RELEASES_DIR, BLACKLIST_FILE)
EOF
)
python3 -c "${run_stage}"

diff --brief -Nr --exclude '*.log' tests/stage-test/stage-key/ "${STAGING_DIR}"

echo "STAGING TEST PASSED"
echo ""
