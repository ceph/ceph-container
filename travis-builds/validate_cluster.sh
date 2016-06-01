#!/usr/bin/env bash
set -xe


# FUNCTIONS
function ceph_status {
  echo "Waiting for Ceph to be ready"
  until docker exec ceph-mon ceph health | grep HEALTH_OK; do
    sleep 1
  done
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
  if docker exec ceph-mon ceph osd dump | grep cephfs; then
    echo "Waiting for the MDS to be ready"
    # NOTE(leseb): metadata server always takes up to 5 sec to run
    # so we first check if the pools exit, from that we assume that
    # the process will start. We stop waiting after 10 seconds.
    counter=10
    while [ $counter -ne 0 ]; do
      if docker exec ceph-mon ceph -s | grep "up:active"; then
        break
      fi
      sleep 1
      let counter=counter-1
   done
  fi
}


# MAIN
ceph_status # wait for the cluster to stabilize

test_mon
test_osd
test_rgw
test_mds

ceph_status # wait again for the cluster to stabilize (mds pools)

if [[ "$(docker ps | grep ceph- | wc -l)" -ne 4 ]]; then
  docker ps | grep ceph-
  echo "looks like one container died :("
  echo "please see the previous output to figure out which one"
  exit 1
fi
