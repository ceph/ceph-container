#!/bin/bash
set -ex

#############
# VARIABLES #
#############

CEPH_RELEASES=(luminous)


#############
# FUNCTIONS #
#############

function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASE_IMAGE=centos:7 build
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASE_IMAGE=centos:7 push
}

function build_and_push_latest_bis {
  True
}

function push_ceph_imgs_latests {
  True
}


########
# MAIN #
########

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./
# shellcheck disable=SC1091
source "$SCRIPT_DIR"/build-push-ceph-container-imgs.sh
