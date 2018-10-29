#!/usr/bin/env bash
set -xe


#############
# FUNCTIONS #
#############
function get_cluster_name {
  cluster=$(docker exec ceph-demo grep -R fsid /etc/ceph/ | egrep -o '^[^.]*')
  DOCKER_COMMAND="docker exec ceph-demo ceph --cluster $(basename $cluster)"
}

function wait_for_daemon () {
  timeout=20
  daemon_to_test=$1
  while [ $timeout -ne 0 ]; do
    if eval $daemon_to_test; then
      return 0
    fi
    sleep 1
    let timeout=timeout-1
  done
  return 1
}

function get_ceph_version {
  # shellcheck disable=SC2046
  echo $($DOCKER_COMMAND --version | grep -Eo '[0-9][0-9]\.[0-9]')
}

function ceph_status {
  echo "Waiting for Ceph to be ready"
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND health | grep -sq HEALTH_OK")
}

function test_demo_mon {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq quorum")
}

function test_demo_osd {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq '1 osds: 1 up.*., 1 in.*.'")
}

function test_demo_rgw {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'rgw:'")
}

function test_demo_mds {
  echo "Waiting for the MDS to be ready"
  # NOTE(leseb): metadata server always takes up to 5 sec to run
  # so we first check if the pools exit, from that we assume that
  # the process will start. We stop waiting after 10 seconds.
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND osd dump | grep -sq cephfs && $DOCKER_COMMAND -s | grep -sq 'up:active'")
}

function test_demo_rbd_mirror {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'rbd-mirror:'")
}

function test_demo_mgr {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'mgr:'")
}


########
# MAIN #
########
get_cluster_name
ceph_status # wait for the cluster to stabilize
test_demo_mon
test_demo_osd
test_demo_rgw
test_demo_mds
test_demo_rbd_mirror
ceph_version=$(get_ceph_version)
if [[ $(echo $ceph_version '>' 10.2 | bc -l) == 1 ]] ; then
  test_demo_mgr
fi
ceph_status # wait again for the cluster to stabilize (mds pools)

if ! docker ps | grep ceph-demo; then
  echo "It looks like ceph-demo container died :("
  exit 1
fi

echo "Ceph is up and running, have a look!"
$DOCKER_COMMAND -s
