#!/usr/bin/env bash
set -xe


# FUNCTIONS
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

function ceph_status {
  echo "Waiting for Ceph to be ready"
  return $(wait_for_daemon "$DOCKER_COMMAND health | grep -sq HEALTH_OK")
}

function test_demo_mon {
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq quorum")
}

function test_demo_osd {
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq '1 osds: 1 up, 1 in'")
}

function test_demo_rgw {
  return $(wait_for_daemon "$DOCKER_COMMAND osd dump | grep -sq rgw")
}

function test_demo_mds {
  echo "Waiting for the MDS to be ready"
  # NOTE(leseb): metadata server always takes up to 5 sec to run
  # so we first check if the pools exit, from that we assume that
  # the process will start. We stop waiting after 10 seconds.
  return $(wait_for_daemon "$DOCKER_COMMAND osd dump | grep -sq cephfs && $DOCKER_COMMAND -s | grep -sq 'up:active'")
}

function test_demo_rbd_mirror {
  return $(ps aux | grep -sq [r]bd-mirror)
}

# MAIN
get_cluster_name
ceph_status # wait for the cluster to stabilize
test_demo_mon
test_demo_osd
test_demo_rgw
test_demo_mds
test_demo_rbd_mirror
ceph_status # wait again for the cluster to stabilize (mds pools)

if ! docker ps | grep ceph-demo; then
  echo "It looks like ceph-demo container died :("
  exit 1
fi

echo "Ceph is up and running, have a look!"
$DOCKER_COMMAND -s
