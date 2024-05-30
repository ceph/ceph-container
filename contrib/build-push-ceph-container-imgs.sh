#!/bin/bash
# vim: set expandtab ts=2 sw=2 :

set -ex

#############
# VARIABLES #
#############
function require {
  if [[ -z "${!1}" ]] ; then
    echo "Required variable $1 not set, exiting"
    exit 1
  fi
}

CI_CONTAINER=${CI_CONTAINER:=false}
if ${CI_CONTAINER} ; then
  # save the ceph branch, from the parent job
  CEPH_BRANCH=${BRANCH}
  # must be set by caller (perhaps another Jenkins build job)
  # BRANCH (as above, the Ceph branch)
  # SHA1 (sha1 corresponding to the Ceph branch)
  # OSD_FLAVOR (choose between default and crimson flavor)
  # CONTAINER_REPO_HOSTNAME="quay.io"
  # CONTAINER_REPO_ORGANIZATION="ceph-ci"
  # CONTAINER_REPO_USERNAME=user
  # CONTAINER_REPO_PASSWORD=password
  for v in BRANCH SHA1 CONTAINER_REPO_HOSTNAME CONTAINER_REPO_ORGANIZATION \
    CONTAINER_REPO_USERNAME CONTAINER_REPO_PASSWORD; do
    require $v
  done
fi

# Push to the quay.io registry by default
REGISTRY="quay.io"
REGISTRY_ORG="ceph"

# backward compatibility; script expected DOCKER_HUB names to be set
CONTAINER_REPO_HOSTNAME=${CONTAINER_REPO_HOSTNAME:-$REGISTRY}
CONTAINER_REPO_ORGANIZATION=${CONTAINER_REPO_ORGANIZATION:-$REGISTRY/$REGISTRY_ORG}
CONTAINER_REPO_USERNAME=${CONTAINER_REPO_USERNAME:-$REGISTRY_USERNAME}
CONTAINER_REPO_PASSWORD=${CONTAINER_REPO_PASSWORD:-$REGISTRY_PASSWORD}

# GIT_BRANCH is typically 'origin/main', we strip the variable to only get 'main'
CONTAINER_BRANCH="${GIT_BRANCH#*/}"
CONTAINER_SHA=$(git rev-parse --short HEAD)
TAGGED_HEAD=false # does HEAD is on a tag ?
DEVEL=${DEVEL:=false}
# flavor based on OSD type proporgated by ceph-build
OSD_FLAVOR=${OSD_FLAVOR:=default}

if [ -z "$CEPH_RELEASES" ]; then
  # NEVER change 'main' position in the array, this will break the 'latest' tag
  CEPH_RELEASES=(main quincy reef)
fi

HOST_ARCH=$(uname -m)
BUILD_ARM= # Set this variable to anything if you want to build the ARM images too


#############
# FUNCTIONS #
#############

function _centos_release {
  local release=$1

  # when building for CI, really we want to build on the same base
  # that the build is using; that's the major version of the
  # build host itself.  Grab it from /etc/os-release.
  if ${CI_CONTAINER}; then
    echo "${VERSION_ID}"
    return
  fi
  case  "${release}" in

    *luminous*)
      echo 7
      ;;
    *mimic*)
      echo 7
      ;;
    *nautilus*)
      echo 7
      ;;
    *)
      echo 9
      ;;
  esac
}

function cleanup_previous_run {
  make clean.all || true
}

declare -F install_docker ||
function install_docker {
  if [[ -x /usr/bin/yum ]] ; then
    sudo yum install -y docker
  else
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --force-yes docker-ce
  fi
  sudo systemctl unmask docker
  sudo systemctl start docker || sudo systemctl restart docker
  sudo systemctl status --no-pager docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function install_podman {

  if ${CI_CONTAINER}; then
    if [[ "${VERSION_ID}" == "8" ]] ; then
      sudo dnf module enable -y container-tools:rhel8
    fi
  fi

  # now install it
  sudo dnf install -y podman podman-docker

  if ${CI_CONTAINER}; then
    # if we actually uninstalled above, it removed our custom registries.conf.
    # Luckily it saved a copy
    if [[ -f /etc/containers/registries.conf.rpmsave ]]; then
      sudo mv /etc/containers/registries.conf.rpmsave /etc/containers/registries.conf
    fi
  fi
}

function login_registry {
  echo "Login in the registry"
  docker login -u "$CONTAINER_REPO_USERNAME" -p "$CONTAINER_REPO_PASSWORD" "${CONTAINER_REPO_HOSTNAME}"
}

function enable_experimental_docker_cli {
  if ! grep "experimental" "$HOME"/.docker/config.json; then
    sed -i '$i,"experimental": "enabled"' "$HOME"/.docker/config.json
  fi
}

declare -F build_ceph_imgs  ||
function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  CENTOS_RELEASE="$(_centos_release "${CEPH_BRANCH}")"
  if ${CI_CONTAINER}; then
    if [ -z "$CONTAINER_FLAVOR" ]; then
      CONTAINER_FLAVOR=${CEPH_BRANCH},centos,"${CENTOS_RELEASE}"
    else
      IFS="," read -r ceph_branch distro distro_release <<< "${CONTAINER_FLAVOR}"
      if [ "${ceph_branch}" != "${BRANCH}" ]; then
        echo "branch \"${ceph_branch}\" in \$CONTAINER_FLAVOR does not match with \$BRANCH \"${BRANCH}\""
        exit 1
      fi
      if [ "${distro}" != "centos" ]; then
        echo "distro \"${distro}\"in \$CONTAINER_FLAVOR is not supported yet"
        exit 1
      fi
    fi

    make FLAVORS="${CONTAINER_FLAVOR}" \
         BASEOS_TAG=stream"${CENTOS_RELEASE}" \
         CEPH_DEVEL="true" \
         OSD_FLAVOR="${OSD_FLAVOR}" \
         RELEASE="${RELEASE}" \
         TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" \
         IMAGES_TO_BUILD=daemon-base \
         build.parallel
  else
    make BASEOS_TAG=stream"${CENTOS_RELEASE}" CEPH_DEVEL="${DEVEL}" RELEASE="${RELEASE}" BASEOS_REGISTRY="${CONTAINER_REPO_HOSTNAME}/centos" BASEOS_REPO=centos TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" IMAGES_TO_BUILD="daemon-base demo" build.parallel
  fi
  docker images
}

declare -F push_ceph_imgs ||
function push_ceph_imgs {
  echo "Push Ceph container image(s) to the registry"
  make BASEOS_TAG=stream"${CENTOS_RELEASE}" RELEASE="$RELEASE" BASEOS_REGISTRY="${CONTAINER_REPO_HOSTNAME}/centos" BASEOS_REPO=centos TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" IMAGES_TO_BUILD="daemon-base demo" push.parallel
}

declare -F push_ceph_imgs_latest ||
function push_ceph_imgs_latest {
  local latest_name

  if [ -z "$CONTAINER_FLAVOR" ]; then
    distro=centos
    distro_release=$(_centos_release "${BRANCH}")
  else
    IFS="," read -r ceph_branch distro distro_release <<< "${CONTAINER_FLAVOR}"
  fi
  # local_tag should match with daemon_img defined in maint-lib/makelib.mk
  local_tag=${CONTAINER_REPO_ORGANIZATION}/daemon-base:${RELEASE}-${CEPH_VERSION}-${distro}-stream${distro_release}-${HOST_ARCH}
  full_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${RELEASE}-${distro}-stream${distro_release}-${HOST_ARCH}-devel
  branch_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${BRANCH}
  sha1_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${SHA1}
  # for centos9, while we're still building centos8, add -centos9 to branch and sha1 tags
  # to avoid colliding with the existing distrover-less tags for the c8 containers
  if [[ ${distro_release} == "9" ]] ; then
    branch_repo_tag=${branch_repo_tag}-centos9
    sha1_repo_tag=${sha1_repo_tag}-centos9
  fi
  # add aarch64 suffix for short tags to allow coexisting arches
  if [[ ${HOST_ARCH} == "aarch64" ]] ; then
    branch_repo_tag=${branch_repo_tag}-aarch64
    sha1_repo_tag=${sha1_repo_tag}-aarch64
  fi
  if [[ "${OSD_FLAVOR}" == "crimson" ]]; then
    if [[ "${HOST_ARCH}" == "x86_64" ]]; then
      sha1_flavor_repo_tag=${sha1_repo_tag}-${OSD_FLAVOR}
      docker tag "$local_tag" "$sha1_flavor_repo_tag"
      docker push "$sha1_flavor_repo_tag"
    fi
  elif [[ "${distro_release}" == "7" ]]; then
    docker tag "$local_tag" "$full_repo_tag"
    docker push "$full_repo_tag"
  else
    docker tag "$local_tag" "$full_repo_tag"
    docker push "$full_repo_tag"
    docker tag "$local_tag" "$branch_repo_tag"
    docker tag "$local_tag" "$sha1_repo_tag"
    docker push "$branch_repo_tag"
    docker push "$sha1_repo_tag"
  fi
  return
}

declare -F wait_for_arm_images ||
function wait_for_arm_images {
  if [ -z "$BUILD_ARM" ]; then
    echo "ARM build is disabled, don't wait for arm images"
    return
  fi
  echo "Waiting for ARM64 images to be ready"
  set -e
  CENTOS_RELEASE=$(_centos_release "${CEPH_RELEASES[-1]}")
  until docker pull "${CONTAINER_REPO_ORGANIZATION}"/daemon:"$RELEASE"-"${CEPH_RELEASES[-1]}"-centos-stream"${CENTOS_RELEASE}"-aarch64; do
    echo -n .
    sleep 30
  done
  set +e
}

declare -F create_registry_manifest ||
function create_registry_manifest {
  enable_experimental_docker_cli
  # This should normally work, by the time we get here the arm64 image should have been built and pushed
  # IIRC docker manisfest will fail if the image does not exist
  rm -rvf ~/.docker/manifests
  for image in daemon-base demo; do
    for ceph_release in "${CEPH_RELEASES[@]}"; do
      TARGET_RELEASE="${CONTAINER_REPO_ORGANIZATION}/${image}:${RELEASE}-${ceph_release}-centos-stream$(_centos_release "${ceph_release}")"
      DOCKER_IMAGES="$TARGET_RELEASE ${TARGET_RELEASE}-x86_64"

      # Let's add ARM images if being built
      if [ -n "$BUILD_ARM" ]; then
        DOCKER_IMAGES="$DOCKER_IMAGES ${TARGET_RELEASE}-aarch64"
      fi

      #shellcheck disable=SC2086
      docker manifest create $DOCKER_IMAGES
      if [ -n "$BUILD_ARM" ]; then
        docker manifest annotate --variant v8 "${TARGET_RELEASE}" "${TARGET_RELEASE}-aarch64"
      fi
      docker manifest push "$TARGET_RELEASE"
    done
  done
}


########
# MAIN #
########

# set global for use in several functions above
eval "$(grep VERSION_ID= /etc/os-release)"

if [[ -x /usr/bin/dnf ]] ; then
  install_podman
else
  install_docker
fi
cleanup_previous_run
login_registry
if ${CI_CONTAINER}; then
  RELEASE=${CEPH_BRANCH}-${SHA1:0:7}
  top_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
  CEPH_VERSION=$(bash "${top_dir}"/maint-lib/ceph_version.sh "${CEPH_BRANCH}" CEPH_VERSION)
else
  echo "Building a devel Ceph container image based on branch $CONTAINER_BRANCH and commit $CONTAINER_SHA"
  RELEASE="$CONTAINER_BRANCH-$CONTAINER_SHA"
fi
build_ceph_imgs
# With devel builds we only push latest builds.
# arm64 aren't present on shaman/chacra so we don't
# need to create a registry manifest
if ! ( ${DEVEL} || ${CI_CONTAINER} ) ; then
  push_ceph_imgs
  wait_for_arm_images
  create_registry_manifest
fi
# If we run on a tagged head, we should not push the 'latest' tag
if $TAGGED_HEAD; then
  echo "Don't push latest as we run on a tagged head"
  exit 0
fi

if ${CI_CONTAINER} ; then
  push_ceph_imgs_latest
fi
