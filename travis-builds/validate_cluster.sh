#!/usr/bin/env bash
set -xe


# FUNCTIONS
function ceph_status {
  echo "waiting for ceph to be ready"
  until docker exec ceph-mon ceph health | grep HEALTH_OK; do
    echo -n "."
    sleep 1
  done
}

function test_mon {
  docker exec ceph-mon ceph -s | grep -q 'quorum'
}

function test_osd {
  docker exec ceph-mon ceph -s | grep -q "1 osds: 1 up, 1 in"
}

function test_rgw {
  docker exec ceph-mon ceph osd dump | grep -q "rgw"
}

function test_mds {
  docker exec ceph-mon ceph osd dump | grep -q cephfs
  docker exec ceph-mon ceph -s | grep -q 'up:active'
}


# MAIN
ceph_status # wait for the cluster to stabilize

test_mon
test_osd
test_rgw
test_mds

if [[ "$(docker ps | grep ceph- | wc -l)" -ne 4 ]]; then
  docker ps | grep ceph-
  echo "looks like one container died :("
  echo "please see the previous output to figure out which one"
  exit 1
fi

docker exec ceph-mon ceph -s
