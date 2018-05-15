#!/bin/bash
set -ex

#############
# VARIABLES #
#############

CEPH_RELEASES=(luminous)


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
  make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASEOS_REPO=centos build
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make DAEMON_BASE_TAG=daemon-base:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 DAEMON_TAG=daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64 RELEASE="$RELEASE" FLAVORS="${CEPH_RELEASES[-1]},centos-arm64,7" BASEOS_REPO=centos push
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
