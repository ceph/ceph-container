#!/bin/bash
set -ex


#############
# FUNCTIONS #
#############

function install_docker {
  sudo apt-get install -y --force-yes docker.io
  sudo systemctl start docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function login_docker_hub {
  echo "Login in the Docker Hub"
  docker login -u "$DOCKER_HUB_USERNAME" -p "$DOCKER_HUB_PASSWORD"
}

function build_ceph_imgs {
  echo "Build ceph container images"
  make build.parallel
}

function push_ceph_imgs {
  echo "Push ceph container images to the Docker Hub registry"
  make push
}


########
# MAIN #
########

install_docker
login_docker_hub
build_ceph_imgs
push_ceph_imgs
