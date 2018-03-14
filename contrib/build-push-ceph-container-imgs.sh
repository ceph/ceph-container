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

function create_head_or_point_release {
  local latest_tag
  # We test if we are running on a tagged commit
  # if so, we build images with this particular tag
  # otherwise we just build using the branch name and the latest commit sha1
  # We use the commit sha1 on the devel image so we can have multiple tags
  # instead of overriding the previous one.
  set +e
  latest_tag=$(git describe --exact-match HEAD --tags --long 2>/dev/null)
  # shellcheck disable=SC2181
  if [ "$?" -eq 0 ]; then
    set -e
    echo "Building a release Ceph container image based on tag $latest_tag"
    RELEASE="$latest_tag"
  else
    set -e
    echo "Building a devel Ceph container image based on branch $GIT_BRANCH and commit $GIT_COMMIT"
    RELEASE="$GIT_BRANCH-$GIT_COMMIT"
  fi
}

function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  make RELEASE="$RELEASE" build.parallel
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make -j "$(nproc)" RELEASE="$RELEASE" push

  for i in daemon-base daemon; do
    tag=ceph/$i:${GIT_BRANCH}-${GIT_COMMIT}-luminous-ubuntu-16.04-amd64
    # tag latest daemon-base and daemon images
    docker tag "$tag" ceph/$i:latest

    # push latest images to the Docker Hub
    docker push ceph/$i:latest
  done
}


########
# MAIN #
########

install_docker
login_docker_hub
create_head_or_point_release
build_ceph_imgs
push_ceph_imgs
