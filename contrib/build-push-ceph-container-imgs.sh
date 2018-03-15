#!/bin/bash
set -ex


#############
# VARIABLES #
#############

# GIT_BRANCH is typically 'origin/master', we strip the variable to only get 'master'
BRANCH="${GIT_BRANCH#*/}"
LATEST_COMMIT_SHA=$(git rev-parse --short HEAD)


#############
# FUNCTIONS #
#############

function cleanup_previous_run {
  make clean.all || true
}

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
  # We test if we are running on a tagged commit
  # if so, we build images with this particular tag
  # otherwise we just build using the branch name and the latest commit sha1
  # We use the commit sha1 on the devel image so we can have multiple tags
  # instead of overriding the previous one.
  set +e
  LATEST_TAG=$(git describe --exact-match HEAD --tags 2>/dev/null)
  # shellcheck disable=SC2181
  if [ "$?" -eq 0 ]; then
    set -e
    # find branch associated to that tag
    BRANCH=$(git branch -r --contains tags/"$LATEST_TAG" | grep -Eo 'stable-[0-9].[0-9]')
    echo "Building a release Ceph container image based on branch $BRANCH and tag $LATEST_TAG"
    RELEASE="$LATEST_TAG-$BRANCH"
  else
    set -e
    echo "Building a devel Ceph container image based on branch $BRANCH and commit $LATEST_COMMIT_SHA"
    RELEASE="$BRANCH-$LATEST_COMMIT_SHA"
  fi
}

function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  make RELEASE="$RELEASE" build.parallel
  docker images
}

function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make RELEASE="$RELEASE" push.parallel

  for i in daemon-base daemon; do
    tag=ceph/$i:${BRANCH}-${LATEST_COMMIT_SHA}-luminous-ubuntu-16.04-x86_64
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
cleanup_previous_run
login_docker_hub
create_head_or_point_release
build_ceph_imgs
push_ceph_imgs
