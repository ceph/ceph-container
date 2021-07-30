#!/usr/bin/env bash
set -xe


#############
# FUNCTIONS #
#############
function get_cluster_name {
  cluster=$(docker exec ceph-demo grep -R fsid /etc/ceph/ | grep -Eo '^[^.]*')
  DOCKER_COMMAND="docker exec ceph-demo ceph --connect-timeout 3 --cluster $(basename "$cluster")"
}

function wait_for_daemon () {
  timeout=90
  daemon_to_test=$1
  while [ $timeout -ne 0 ]; do
    if eval "$daemon_to_test"; then
      return 0
    fi
    sleep 1
    (( timeout=timeout-1 ))
  done
  return 1
}

function get_ceph_version {
  # shellcheck disable=SC2046
  $DOCKER_COMMAND --version | grep -Eo '[0-9][0-9]\.[0-9]'
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
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq '2 osds: 2 up.*, 2 in.*'")
}

function test_demo_rgw {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'rgw:'")
}

function test_demo_nfs {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'rgw-nfs:'")
}

function test_demo_mds {
  echo "Waiting for the MDS to be ready"
  # NOTE(leseb): metadata server always takes up to 5 sec to run
  # so we first check if the pools exit, from that we assume that
  # the process will start. We stop waiting after 10 seconds.
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND osd dump | grep -sq cephfs && $DOCKER_COMMAND -s | grep -sq 'mds: 1/1 daemons up'")
}

function test_demo_rbd_mirror {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'rbd-mirror:'")
}

function test_demo_mgr {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND -s | grep -sq 'mgr:'")
}

function test_demo_rest_api {
  key=$($DOCKER_COMMAND restful list-keys | jq -r .demo)
  docker exec ceph-demo curl -s --connect-timeout 1 -u demo:"$key" -k https://0.0.0.0:8003/server
  # shellcheck disable=SC2046
  return $(wait_for_daemon "$DOCKER_COMMAND mgr dump | grep -sq 'restful\": \"https://.*:8003'")
}

function test_demo_crash {
  # shellcheck disable=SC2046
  return $(wait_for_daemon "ps aux | grep -sq [c]eph-crash")
}

########
# MAIN #
########
get_cluster_name
ceph_status # wait for the cluster to stabilize
get_ceph_version
test_demo_mon
test_demo_osd
test_demo_rgw
test_demo_mds
test_demo_nfs
test_demo_rbd_mirror
test_demo_mgr
test_demo_rest_api
test_demo_crash
ceph_status # wait again for the cluster to stabilize (mds pools)

if ! docker ps | grep ceph-demo; then
  echo "It looks like ceph-demo container died :("
  exit 1
fi

echo "Ceph is up and running, have a look!"
$DOCKER_COMMAND -s
