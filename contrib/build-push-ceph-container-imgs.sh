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
CEPH_RELEASES_BIS=(jewel luminous) # list of releases that need a "bis" image for ceph-ansible
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

function compare_docker_hub_and_github_tags {
  # build an array with the list of tags from github
  for tag_github in $(grep_sort_tags "git ls-remote --tags"); do
    tags_github_array+=("$tag_github")
  done

  # download cn to list docker hub images, it's easier than building the logic in bash...
  # and cn is only 10MB so it doesn't hurt
  curl -L https://github.com/ceph/cn/releases/download/v1.7.0/cn-v1.7.0-cc5ad52-linux-amd64 -o cn
  chmod +x cn

  # build an array with the list of tag from docker hub
  tags_docker_hub="$(grep_sort_tags "./cn image ls -a" | uniq)"
  for tag_docker_hub in $tags_docker_hub; do
    tags_docker_hub_array+=("$tag_docker_hub")
  done

  # we now look into each array and find a possible missing tag
  # the idea is to find if a tag present on github is not present on docker hub
  for i in "${tags_github_array[@]}"; do
    echo "${tags_docker_hub_array[@]}" | grep -q "$i" || tag_to_build+=("$i")
  done

  # if there is an entry we activate TAGGED_HEAD which tells the script to build a release image
  # we must find a single tag only
  if [[ ${#tag_to_build[@]} -eq "1" ]]; then
    TAGGED_HEAD=true
    echo "${tag_to_build[*]} not found! Building it."
  fi

  # if we find more than one release, we should fail and report the problem
  if [[ ${#tag_to_build[@]} -gt "1" ]]; then
    echo "ERROR: it looks like more than one tag are not built, see ${tag_to_build[*]}."
  fi
}

function create_head_or_point_release {
  # We test if there is a new tag available
  # if so, we build images with this particular tag
  # otherwise we just build using the branch name and the latest commit sha1
  # We use the commit sha1 on the devel image so we can have multiple tags
  # instead of overriding the previous one.

  # call compare tags to determine if we need to build a release
  compare_docker_hub_and_github_tags

  # shellcheck disable=SC2181
  if $TAGGED_HEAD; then
    # checkout tag's code
    # using [*] but [0] would work too, also the array's length should be 1 anyway
    # this code is only activated if length is 1 so we are safe
    git checkout refs/tags/"${tag_to_build[*]}"

    # find branch associated to that tag
    BRANCH=$(git branch -r --contains tags/"${tag_to_build[*]}" | grep -Eo 'stable-[0-9].[0-9]')
    echo "Building a release Ceph container image based on branch $BRANCH and tag ${tag_to_build[*]}"
    RELEASE="${tag_to_build[*]}-$BRANCH"
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
  # latest-bis-$ceph_release is needed by ceph-ansible so it can test the restart handlers on an image ID change
  # rebuild latest again to get a different image ID
  for ceph_release in "${CEPH_RELEASES_BIS[@]}"; do
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
