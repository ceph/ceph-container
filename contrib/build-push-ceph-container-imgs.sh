#!/bin/bash
set -ex


#############
# VARIABLES #
#############

# GIT_BRANCH is typically 'origin/master', we strip the variable to only get 'master'
BRANCH="${GIT_BRANCH#*/}"
LATEST_COMMIT_SHA=$(git rev-parse --short HEAD)
TAGGED_HEAD=false # does HEAD is on a tag ?
if [ -z "$CEPH_RELEASES" ]; then CEPH_RELEASES=(jewel kraken luminous mimic); fi
HOST_ARCH=$(uname -m)


#############
# FUNCTIONS #
#############

function cleanup_previous_run {
  make clean.all || true
}

declare -F install_docker ||
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
  if ! grep "experimental" "$HOME"/.docker/config.json; then
    sed -i '$i,"experimental": "enabled"' "$HOME"/.docker/config.json
  fi
}

function grep_sort_tags {
  "$@" | grep -oE 'v[3-9].[0-9]*.[0-9]*$' | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n
}

function find_latest_ceph_release {
  # looking through the repo to determine the latest stable version number
  # since the build pull the latest packages, this will help us adding
  # the release number as part of the image name

  local release_passed=$1

  if [[ "$release_passed" == jewel ]]; then
    release_number=10.2
  elif [[ "$release_passed" == kraken ]]; then
    release_number=11.2
  elif [[ "$release_passed" == luminous ]]; then
    release_number=12.2
  elif [[ "$release_passed" == mimic ]]; then
    release_number=13.2
  elif [[ "$release_passed" == nautilus ]]; then
    release_number=14.2
  else
    echo "Wrong release name: $release_passed"
    exit 1
  fi

  curl -s http://download.ceph.com/rpm-"${release_passed}"/el7/SRPMS/ | grep -Eo "ceph-${release_number}.?.?" | uniq | tail -1
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
  for release in "${CEPH_RELEASES[@]}"; do
    release_number="$(find_latest_ceph_release "$release")"
    make RELEASE="$RELEASE-${release_number}" build
  done
  docker images
}

declare -F push_ceph_imgs ||
function push_ceph_imgs {
  echo "Push Ceph container image(s) to the Docker Hub registry"
  make RELEASE="$RELEASE" push.parallel
}

declare -F build_and_push_latest_bis ||
function build_and_push_latest_bis {
  # latest-bis-$ceph_release is needed by ceph-ansible so it can test the restart handlers on an image ID change
  # rebuild latest again to get a different image ID
  # shellcheck disable=SC2043
  for ceph_release in luminous; do  # I know it's a loop with one element, I'm preparing the ground for the next release
    make RELEASE="$BRANCH"-bis FLAVORS="${ceph_release}",centos,7 build
    docker tag ceph/daemon:"$BRANCH"-bis-"${ceph_release}"-centos-7-"${HOST_ARCH}" ceph/daemon:latest-bis-"$ceph_release"
    docker push ceph/daemon:latest-bis-"$ceph_release"
  done

  # Now let's build the latest
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

declare -F wait_for_arm_images ||
function wait_for_arm_images {
  echo "Waiting for ARM64 images to be ready"
  set -e
  until docker pull ceph/daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-7-aarch64; do
    echo -n .
    sleep 1
  done
  set +e
}

declare -F create_registry_manifest ||
function create_registry_manifest {
  enable_experimental_docker_cli
  # This should normally work, by the time we get here the arm64 image should have been built and pushed
  # IIRC docker manisfest will fail if the image does not exist
  for image in daemon-base daemon; do
    for ceph_release in luminous mimic; do
      docker manifest create ceph/"$image":"$RELEASE"-"$ceph_release"-centos-7 ceph/"$image":"$RELEASE"-"$ceph_release"-centos-7-x86_64 ceph/"$image":"$RELEASE"-"$ceph_release"-centos-7-aarch64
      docker manifest push ceph/"$image":"$RELEASE"-"$ceph_release"-centos-7
    done
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
wait_for_arm_images
create_registry_manifest
# If we run on a tagged head, we should not push the 'latest' tag
if $TAGGED_HEAD; then
  echo "Don't push latest as we run on a tagged head"
  exit 0
fi
push_ceph_imgs_latests
build_and_push_latest_bis
