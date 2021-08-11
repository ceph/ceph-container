#!/bin/bash
set -ex

#############
# VARIABLES #
#############



#############
# FUNCTIONS #
#############

function install_docker {
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --force-yes docker.io
  sudo systemctl start docker
  sudo systemctl status docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  for ceph_release in "${CEPH_RELEASES[@]}"; do
    CENTOS_RELEASE=$(_centos_release "${ceph_release}")
    make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${ceph_release}"-centos-"${CENTOS_RELEASE}"-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${ceph_release}"-centos-"${CENTOS_RELEASE}"-aarch64 RELEASE="${RELEASE}" FLAVORS="${ceph_release},centos-arm64,${CENTOS_RELEASE}" BASEOS_REGISTRY="${CONTAINER_REPO_HOSTNAME}/centos" BASEOS_REPO=centos TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" build
  done
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the registry"
  for ceph_release in "${CEPH_RELEASES[@]}"; do
    CENTOS_RELEASE=$(_centos_release "${ceph_release}")
    make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${ceph_release}"-centos-"${CENTOS_RELEASE}"-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${ceph_release}"-centos-"${CENTOS_RELEASE}"-aarch64 RELEASE="${RELEASE}" FLAVORS="${ceph_release},centos-arm64,${CENTOS_RELEASE}" BASEOS_REGISTRY="${CONTAINER_REPO_HOSTNAME}/centos" BASEOS_REPO=centos TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" push
  done
}

function build_and_push_latest_bis {
  return
}

function push_ceph_imgs_latest {
  return
}

function create_registry_manifest {
  return
}

function wait_for_arm_images {
  return
}


########
# MAIN #
########

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./
# shellcheck disable=SC1091
source "$SCRIPT_DIR"/build-push-ceph-container-imgs.sh
