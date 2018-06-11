#!/bin/bash
set -ex

#############
# VARIABLES #
#############

CEPH_RELEASES=(luminous mimic)


#############
# FUNCTIONS #
#############

function install_docker {
  sudo apt-get install -y --force-yes docker.io
  sudo systemctl start docker
  sudo systemctl status docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  for ceph_release in "${CEPH_RELEASES[@]}"; do
    make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${ceph_release}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${ceph_release}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${ceph_release},centos-arm64,7" BASEOS_REPO=centos build
  done
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  for ceph_release in "${CEPH_RELEASES[@]}"; do
    make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${ceph_release}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${ceph_release}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${ceph_release},centos-arm64,7" BASEOS_REPO=centos push
  done
}

function build_and_push_latest_bis {
  return
}

function push_ceph_imgs_latests {
  return
}

function create_registry_manifest {
  return
}


########
# MAIN #
########

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./
# shellcheck disable=SC1091
source "$SCRIPT_DIR"/build-push-ceph-container-imgs.sh
