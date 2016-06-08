#!/usr/bin/env bash
set -xe


# FUNCTIONS
function wait_for_daemon () {
  timeout=10
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
  return $(wait_for_daemon "docker exec ceph-mon ceph health | grep -sq HEALTH_OK")
}

function test_mon {
  docker exec ceph-mon ceph -s | grep "quorum"
}

function test_osd {
  docker exec ceph-mon ceph -s | grep "1 osds: 1 up, 1 in"
}

function test_rgw {
  docker exec ceph-mon ceph osd dump | grep "rgw"
}

function test_mds {
  echo "Waiting for the MDS to be ready"
  # NOTE(leseb): metadata server always takes up to 5 sec to run
  # so we first check if the pools exit, from that we assume that
  # the process will start. We stop waiting after 10 seconds.
  return $(wait_for_daemon "docker exec ceph-mon ceph osd dump | grep -sq cephfs && docker exec ceph-mon ceph -s | grep -sq 'up:active'")
}

function test_demo {
  docker exec ceph-demo ceph health | grep HEALTH_OK
  docker exec ceph-demo ceph -s | grep "quorum"
  docker exec ceph-demo ceph -s | grep "1 osds: 1 up, 1 in"
  docker exec ceph-demo ceph osd dump | grep "rgw"
  return $(wait_for_daemon "docker exec ceph-demo ceph osd dump | grep cephfs && docker exec ceph-demo ceph -s | grep 'up:active'")
  return $(wait_for_daemon "docker exec ceph-demo ceph health | grep HEALTH_OK")
}

# MAIN
ceph_status # wait for the cluster to stabilize

test_mon
test_osd
test_rgw
test_mds
test_demo

ceph_status # wait again for the cluster to stabilize (mds pools)

if [[ "$(docker ps | grep ceph- | wc -l)" -ne 5 ]]; then
  docker ps | grep ceph-
  echo "looks like one container died :("
  echo "please see the previous output to figure out which one"
  exit 1
fi
