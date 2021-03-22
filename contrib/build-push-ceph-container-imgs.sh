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

# backward compatibility; script expected DOCKER_HUB names to be set
CONTAINER_REPO_USERNAME=${CONTAINER_REPO_USERNAME:-$DOCKER_HUB_USERNAME}
CONTAINER_REPO_PASSWORD=${CONTAINER_REPO_PASSWORD:-$DOCKER_HUB_PASSWORD}

# GIT_BRANCH is typically 'origin/master', we strip the variable to only get 'master'
CONTAINER_BRANCH="${GIT_BRANCH#*/}"
CONTAINER_SHA=$(git rev-parse --short HEAD)
TAGGED_HEAD=false # does HEAD is on a tag ?
DEVEL=${DEVEL:=false}
# flavor based on OSD type proporgated by ceph-build
OSD_FLAVOR=${OSD_FLAVOR:=default}

if [ -z "$CEPH_RELEASES" ]; then
  # NEVER change 'master' position in the array, this will break the 'latest' tag
  CEPH_RELEASES=(master nautilus octopus pacific)
fi

HOST_ARCH=$(uname -m)
BUILD_ARM= # Set this variable to anything if you want to build the ARM images too
CN_RELEASE="v2.3.1"


#############
# FUNCTIONS #
#############

function _centos_release {
  local release=$1
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
      echo 8
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
  sudo systemctl start docker
  sudo systemctl status --no-pager docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}

function install_podman {

  if ${CI_CONTAINER}; then
    # we may need to undo prior packaging hacks.  This code should only
    # have any effect the first time it runs.
    if dnf repolist | grep -q devel_kubic_libcontainers_stable 2>/dev/null
    then

      sudo dnf -y repository-packages devel_kubic_libcontainers_stable remove
      sudo dnf config-manager --disable devel_kubic_libcontainers_stable
    fi
    if dnf repolist | grep -q copr:copr.fedorainfracloud.org:rhcontainerbot:container-selinux 2>/dev/null; then
      sudo dnf -y repository-packages copr:copr.fedorainfracloud.org:rhcontainerbot:container-selinux remove
      sudo dnf config-manager --disable copr:copr.fedorainfracloud.org:rhcontainerbot:container-selinux
    fi
    sudo dnf module enable -y container-tools:rhel8
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

function login_docker_hub {
  echo "Login in the Docker Hub"
  docker login -u "$CONTAINER_REPO_USERNAME" -p "$CONTAINER_REPO_PASSWORD" "${CONTAINER_REPO_HOSTNAME}"
}

function enable_experimental_docker_cli {
  if ! grep "experimental" "$HOME"/.docker/config.json; then
    sed -i '$i,"experimental": "enabled"' "$HOME"/.docker/config.json
  fi
}

function grep_sort_tags {
  "$@" | grep -oE 'v[3-9].[0-9]*.[0-9]*|v[3-9].[0-9]*.[0-9](alpha|beta|rc)[0-9]{1,2}?' | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n
}

function download_cn {
  local cn_link
  cn_link="https://github.com/ceph/cn/releases/download/${CN_RELEASE}/cn-${CN_RELEASE}-linux-amd64"
  if [[ $(arch) == "aarch64" ]]; then
    cn_link="https://github.com/ceph/cn/releases/download/${CN_RELEASE}/cn-${CN_RELEASE}-linux-arm64"
  fi
  curl -L "$cn_link" -o cn
  chmod +x cn
}

function compare_docker_hub_and_github_tags {
  # build an array with the list of tags from github
  for tag_github in $(grep_sort_tags git ls-remote --tags --refs 2>/dev/null); do
    tags_github_array+=("$tag_github")
  done

  # download cn to list docker hub images, it's easier than building the logic in bash...
  # and cn is only 10MB so it doesn't hurt
  download_cn

  # build an array with the list of tag from docker hub
  tags_docker_hub="$(grep_sort_tags ./cn image ls -a | uniq)"
  for tag_docker_hub in $tags_docker_hub; do
    tags_docker_hub_array+=("$tag_docker_hub")
  done

  # we now look into each array and find a possible missing tag
  # the idea is to find if a tag present on github is not present on docker hub
  for i in "${tags_github_array[@]}"; do
    # the grep has a conditionnal on either the explicit match last character is the end of the line OR
    # it has a space after it so we cover the case where the tag that matches is placed at the end
    # of the line or the first one
    echo "${tags_docker_hub_array[@]}" | grep -qoE "${i}$|${i} " || tag_to_build+=("$i")
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
    CONTAINER_BRANCH=$(git branch -r --contains tags/"${tag_to_build[*]}" | grep -Eo 'stable-[0-9].[0-9]')
    echo "Building a release Ceph container image based on branch $CONTAINER_BRANCH and tag ${tag_to_build[*]}"
    RELEASE="${tag_to_build[*]}-$CONTAINER_BRANCH"
    # (todo): remove this when we have a better solution like running
    # the build script directly from the right branch.
    if [ "${CONTAINER_BRANCH}" == "stable-3.2" ]; then
      CEPH_RELEASES=(luminous mimic)
    elif [ "${CONTAINER_BRANCH}" == "stable-4.0" ]; then
      CEPH_RELEASES=(nautilus)
    elif [ "${CONTAINER_BRANCH}" == "stable-5.0" ]; then
      CEPH_RELEASES=(octopus)
    elif [ "${CONTAINER_BRANCH}" == "stable-6.0" ]; then
      CEPH_RELEASES=(pacific)
    fi
  else
    set -e
    echo "Building a devel Ceph container image based on branch $CONTAINER_BRANCH and commit $CONTAINER_SHA"
    RELEASE="$CONTAINER_BRANCH-$CONTAINER_SHA"
  fi
}

declare -F build_ceph_imgs  ||
function build_ceph_imgs {
  echo "Build Ceph container image(s)"
  if ${CI_CONTAINER}; then
    if [ -z "$CONTAINER_FLAVOR" ]; then
      CONTAINER_FLAVOR=${CEPH_BRANCH},centos,$(_centos_release "${CEPH_BRANCH}")
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
         CEPH_DEVEL="true" \
         OSD_FLAVOR=${OSD_FLAVOR} \
         RELEASE="${RELEASE}" \
         TAG_REGISTRY="${CONTAINER_REPO_ORGANIZATION}" \
         IMAGES_TO_BUILD=daemon-base \
         build.parallel
  else
    make CEPH_DEVEL=${DEVEL} RELEASE="${RELEASE}" build.parallel
  fi
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
  for ceph_release in "${CEPH_RELEASES[@]}"; do
    CENTOS_RELEASE=$(_centos_release "${ceph_release}")
    make RELEASE="$CONTAINER_BRANCH"-bis FLAVORS="${ceph_release}",centos,"${CENTOS_RELEASE}" build
    docker tag ceph/daemon:"$CONTAINER_BRANCH"-bis-"${ceph_release}"-centos-"${CENTOS_RELEASE}"-"${HOST_ARCH}" ceph/daemon:latest-bis-"$ceph_release"
    docker push ceph/daemon:latest-bis-"$ceph_release"
  done

  # Now let's build the latest
  CENTOS_RELEASE=$(_centos_release "${CEPH_RELEASES[-1]}")
  make RELEASE="$CONTAINER_BRANCH"-bis FLAVORS="${CEPH_RELEASES[-1]}",centos,"${CENTOS_RELEASE}" build
  docker tag ceph/daemon:"$CONTAINER_BRANCH"-bis-"${CEPH_RELEASES[-1]}"-centos-"${CENTOS_RELEASE}"-"${HOST_ARCH}" ceph/daemon:latest-bis
  docker push ceph/daemon:latest-bis
}

declare -F push_ceph_imgs_latest ||
function push_ceph_imgs_latest {
  local latest_name

  if ${CI_CONTAINER} ; then
    if [ -z "$CONTAINER_FLAVOR" ]; then
      distro=centos
      distro_release=$(_centos_release "${BRANCH}")
    else
      IFS="," read -r ceph_branch distro distro_release <<< "${CONTAINER_FLAVOR}"
    fi
    # local_tag should match with daemon_img defined in maint-lib/makelib.mk
    local_tag=${CONTAINER_REPO_ORGANIZATION}/daemon-base:${RELEASE}-${CEPH_VERSION}-${distro}-${distro_release}-${HOST_ARCH}
    full_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${RELEASE}-${distro}-${distro_release}-${HOST_ARCH}-devel
    branch_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${BRANCH}
    sha1_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${SHA1}
    # add aarch64 suffix for short tags to allow coexisting arches
    if [[ ${HOST_ARCH} == "aarch64" ]] ; then
      branch_repo_tag=${branch_repo_tag}-aarch64
      sha1_repo_tag=${sha1_repo_tag}-aarch64
    fi
    if [[ "${OSD_FLAVOR}" == "crimson" ]]; then
      if [[ "${HOST_ARCH}" == "x86_64" ]]; then
        sha1_flavor_repo_tag=${CONTAINER_REPO_HOSTNAME}/${CONTAINER_REPO_ORGANIZATION}/ceph:${SHA1}-${OSD_FLAVOR}
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
  fi

  for release in "${CEPH_RELEASES[@]}" latest; do
    if [[ "$release" == "latest" ]]; then
      latest_name="latest"
      # Use the last item in the array which corresponds to the latest stable Ceph version
      release=${CEPH_RELEASES[-1]}
    else
      latest_name="latest-$release"
    fi
    if ${DEVEL}; then
      latest_name="${latest_name}-devel"
    fi
    for i in daemon-base daemon; do
      tag=ceph/$i:${CONTAINER_BRANCH}-${CONTAINER_SHA}-$release-centos-$(_centos_release "${release}")-${HOST_ARCH}
      # tag image
      docker tag "$tag" ceph/$i:"$latest_name"

      # push image to the Docker Hub
      docker push ceph/$i:"$latest_name"
    done
  done
}

declare -F wait_for_arm_images ||
function wait_for_arm_images {
  if [ -z "$BUILD_ARM" ]; then
    echo "ARM build is disabled, don't wait for arm images"
    return
  fi
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
    for ceph_release in "${CEPH_RELEASES[@]}"; do
      if [ "${ceph_release}" == "master" ]; then
        continue
      fi
      TARGET_RELEASE="ceph/${image}:${RELEASE}-${ceph_release}-centos-$(_centos_release "${ceph_release}")"
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

if [[ -x /usr/bin/dnf ]] ; then
  install_podman
else
  install_docker
fi
cleanup_previous_run
login_docker_hub
if ${CI_CONTAINER}; then
  RELEASE=${CEPH_BRANCH}-${SHA1:0:7}
  top_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
  CEPH_VERSION=$(bash "${top_dir}"/maint-lib/ceph_version.sh "${CEPH_BRANCH}" CEPH_VERSION)
else
  create_head_or_point_release
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
push_ceph_imgs_latest
# We don't need latest bis tags with ceph devel
if ! ( ${DEVEL} || ${CI_CONTAINER} ); then
  build_and_push_latest_bis
fi
