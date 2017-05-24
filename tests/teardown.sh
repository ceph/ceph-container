#!/bin/bash -x

# shellcheck source=/dev/null
. "$WORKSPACE/.tox_vars"
cd "$CEPH_ANSIBLE_SCENARIO_PATH" || exit 1
vagrant destroy --force
cd "$WORKSPACE" || exit
