#!/bin/bash -x

# shellcheck source=/dev/null
. "$WORKSPACE/.tox_vars"
cd "$CEPH_ANSIBLE_SCENARIO_PATH" || exit 1
vagrant destroy --force
# see https://github.com/ceph/ceph-container/issues/1048
sudo chown -R "$(whoami)" ./staging || true
cd "$WORKSPACE" || exit
