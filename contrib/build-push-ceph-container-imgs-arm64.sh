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
  make RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASE_IMAGE=centos:7 build
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASE_IMAGE=centos:7 push
}

function build_and_push_latest_bis {
  # latest-bis is needed by ceph-ansible so it can test the restart handlers on an image ID change
  # rebuild latest again to get a different image ID
  make RELEASE="$RELEASE"-bis FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASE_IMAGE=centos:7 build
  docker tag ceph/daemon:"$BRANCH"-bis-"${CEPH_RELEASES[-1]}"-centos-arm64-7-${HOST_ARCH} ceph/daemon:latest-bis
  docker push ceph/daemon:latest-bis
}


########
# MAIN #
########

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SCRIPT_DIR/build-push-ceph-container-imgs.sh
