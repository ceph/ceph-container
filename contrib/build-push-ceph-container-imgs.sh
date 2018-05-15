#!/bin/bash
set -ex


#############
# VARIABLES #
#############

# GIT_BRANCH is typically 'origin/master', we strip the variable to only get 'master'
BRANCH="${GIT_BRANCH#*/}"
LATEST_COMMIT_SHA=$(git rev-parse --short HEAD)
TAGGED_HEAD=false # does HEAD is on a tag ?
if [ -z "$CEPH_RELEASES" ]; then CEPH_RELEASES=(jewel kraken luminous); fi
HOST_ARCH=$(uname -m)


#############
# FUNCTIONS #
#############

function cleanup_previous_run {
  make clean.all || true
}

function install_docker {
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  sudo apt-get update
  sudo apt-get install -y --force-yes docker-ce
  sudo systemctl start docker
  sudo systemctl status docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function login_docker_hub {
  echo "Login in the Docker Hub"
  docker login -u "$DOCKER_HUB_USERNAME" -p "$DOCKER_HUB_PASSWORD"
}

function enable_experimental_docker_cli {
  mkdir -p "$HOME/.docker"
  cat <<EOF  > "$HOME/.docker/daemon.json"
{
  "debug" : true,
  "experimental" : true
}
EOF
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
    TAGGED_HEAD=true # Let's remember we run on a tagged head for a later use
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

declare -F build_ceph_imgs  ||
function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  make RELEASE="$RELEASE" build.parallel
  docker images
}

declare -F push_ceph_imgs ||
function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make RELEASE="$RELEASE" push.parallel
}

declare -F build_and_push_latest_bis ||
function build_and_push_latest_bis {
  # latest-bis is needed by ceph-ansible so it can test the restart handlers on an image ID change
  # rebuild latest again to get a different image ID
  make RELEASE="$BRANCH"-bis FLAVORS="${CEPH_RELEASES[-1]}",centos,7 build
  docker tag ceph/daemon:"$BRANCH"-bis-"${CEPH_RELEASES[-1]}"-centos-7-"${HOST_ARCH}" ceph/daemon:latest-bis
  docker push ceph/daemon:latest-bis
}

declare -F push_ceph_imgs_latests ||
function push_ceph_imgs_latests {
  local latest_name
  for release in "${CEPH_RELEASES[@]}" latest; do
    if [[ "$release" == "latest" ]]; then
      latest_name="latest"
      # Use the last item in the array which corresponds to the latest stable Ceph version
      release=${CEPH_RELEASES[-1]}
    else
      latest_name="latest-$release"
    fi
    for i in daemon-base daemon; do
      tag=ceph/$i:${BRANCH}-${LATEST_COMMIT_SHA}-$release-centos-7-${HOST_ARCH}
      # tag image
      docker tag "$tag" ceph/$i:"$latest_name"

      # push image to the Docker Hub
      docker push ceph/$i:"$latest_name"
    done
  done
}

declare -F create_registry_manifest ||
function create_registry_manifest {
  # This should normally work, by the time we get here the arm64 image should have been built and pushed
  # IIRC docker manisfest will fail if the image does not exist
  for image in daemon-base daemon; do
    docker manifest create ceph/"$image":"$RELEASE"-luminous-centos-7 ceph/"$image":"$RELEASE"-luminous-centos-7-x86_64 ceph/"$image":"$RELEASE"-luminous-centos-7-aarch64
    docker manifest push ceph/"$image":"$RELEASE"-luminous-centos-7
  done
}


########
# MAIN #
########

install_docker
cleanup_previous_run
enable_experimental_docker_cli
login_docker_hub
create_head_or_point_release
build_ceph_imgs
push_ceph_imgs
create_registry_manifest
# If we run on a tagged head, we should not push the 'latest' tag
if $TAGGED_HEAD; then
  echo "Don't push latest as we run on a tagged head"
  exit 0
fi
push_ceph_imgs_latests
build_and_push_latest_bis
