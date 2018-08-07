#!/usr/bin/env bash
set -euo pipefail

#---------------------------------------------------------------------------------------------------
# ABOUT
#---------------------------------------------------------------------------------------------------

# Build and push daemon-base images which are tagged with the version of Ceph installed in them.
# Images are intended for Rook and are therefore CentOS-based.
#
# This script will look to see which Ceph package versions are available for given Ceph named
# versions (e.g., luminous, mimic). If any of the available Ceph package versions don't have a
# corresponding image and tag on the registry, the script will build the image and push it to the
# registry. The script will do nothing if images are at parity with packages.
#
# This script can therefore be run on a cron regularly, and very little manual maintenance should be
# necessary unless Ceph RPM releases or images published change. The only maintenance needed is to
# add new Ceph releases to the `FLAVORS_TO_BUILD` variable below.

# This script requires the hypriot/qemu-register container running as per the instructions for Rook
# given in https://github.com/rook/rook/blob/master/INSTALL.md#building-for-other-platforms

# Versioning:
# Versions consist of 2 parts: the Ceph version and the build number following the form
#     v<ceph version>-<build number> (e.g., v12.2.2-4)
#   As a matter of semantics, this script calls the 'v<ceph version>' part the 'version_tag'


#---------------------------------------------------------------------------------------------------
# YOU CAN TUNE A SCRIPT, BUT YOU CAN'T TUNE A FISH
#---------------------------------------------------------------------------------------------------

# This is mostly an internal representation of `FLAVORS_TO_BUILD`. This script builds x86 and arm
# images for centos, so the middle item doesn't really matter except to make this easier to grok at
# first glance.
#   Usage examples:
# luminous,centos,7 = build luminous containers on centos 7
# mimic,centos,7 = build mimic containers on centos 7
# nautilus,centos,8 = build nautilus containers on centos 8
FLAVORS_TO_BUILD="luminous,centos,7 mimic,centos,7"

# Use the ceph library by default
PUSH_LIBRARY="ceph"

# Instead of 'daemon-base', call these images 'ceph' so users don't get these confused with the
# daemon-base and daemon images. This is the registry where manifest images are pushed.
PUSH_REPOSITORY="ceph"

# Manifest images point to the below arch-specific images
AMD64_PUSH_REPOSITORY="${PUSH_REPOSITORY}-amd64"
ARM64_PUSH_REPOSITORY="${PUSH_REPOSITORY}-arm64"

# Push to the docker hub by default
#PUSH_REGISTRY_URL="https://registry.hub.docker.com/"
PUSH_REGISTRY_URL=http://localhost:5000/

# Get this many page entries at a time; this should be high enough that all tags for an image are
# listed without pagination.
ABSURD_PAGE_SIZE=100000



#---------------------------------------------------------------------------------------------------
# FUNCTIONS
#---------------------------------------------------------------------------------------------------

function info () {
  echo "CEPHBUILD - INFO: ${*}"
}

# Return a list of the ceph version strings available on the server as:
#   "12.0.0 12.0.1 12.0.2 12.1.0 ..."
function ceph_versions_on_server () {
  ceph_codename="${1}" ; distro_release="${2}" ; ceph_arch="${3}"
  download_url="http://download.ceph.com/rpm-${ceph_codename}/el${distro_release}/${ceph_arch}/"
  # Curl gives a listing of the URL like below:
  # <a href="ceph-12.2.7-0.el7.x86_64.rpm">ceph-12.2.7-0.el7.x86_64.rpm</a>  17-Jul-2018 14:11  3024
  # The ceph base package can be id'ed uniquely by the text ">ceph-" followed by a version string
  pkg_regex=">ceph-[0-9.]+"
  # pkg_list is returned in the form ">ceph-12.0.0 >ceph-12.0.1 >ceph-12.0.2 ..."
  pkg_list="$(curl --silent "${download_url}" | grep --extended-regexp --only-matching "${pkg_regex}")"
  version_list=""  # version strings only
  for pkg in $pkg_list; do
    version_list="${version_list} ${pkg#>ceph-}"  # strip '>ceph-' text from beginning of pkg names
  done
  info "${version_list}"
}

# Return 0 if the tag exists on the repository; nonzero otherwise
function tag_exists_on_repository () {
  tag="${1}"
  repository="${2}"
  tag_query_url="${PUSH_REGISTRY_URL}/v2/repositories/${PUSH_LIBRARY}/${repository}/tags/${tag}"
  curl --silent --fail --list-only --show-error --location "${tag_query_url}" &> /dev/null
}

# Get all tags matching a given string on the repository
function get_tags_matching () {
  tag_matcher="${1}"
  repository="${2}"
  tag_list_url="${PUSH_REGISTRY_URL}/v2/repositories/${PUSH_LIBRARY}/${repository}/tags/?page_size=${ABSURD_PAGE_SIZE}"
  curl --silent --fail --list-only --show-error --location "${tag_list_url}" &> /dev/null | \
    jq -r ".results[] | select(.name | match(\"${tag_matcher}\")) | .name"
    # jq: From the results of the curl, select all images with a name matching the matcher, and then
    # output the name. Exits success w/ empty string if no matches found.
}

# Given a tag and a version, extract the build number for that version from the tag
# Fail if the version doesn't match up with the tag
function extract_build_number () {
  tag="${1}"
  version_tag="${2}"  # version allows us to verify that the build number version and tag match
  local build_number
  build_number="${tag#${version_tag}-}"  # remove '<version>-' from beginning of string
  _=$(( build_number + 0 ))  # If build is not formatted properly, this will fail gloriously
  echo "${build_number}"
}

# Get the tag matching a version with the highest build number
# Return empty string if no matching version was found
function get_tag_w_highest_build_number () {
  version_tag="${1}"
  repository="${2}"
  tags_matching_version="$(get_tags_matching "${version_tag}" "${repository}")"
  # Sort is safe here because we only get tags matching our specific version
  echo "${tags_matching_version}" | sort | tail -1
}

# Get the next build number for a given Ceph version
# Build number is defined as a dash followed by a build number after a version string
#   e.g. - Ceph version 12.2.2 will be v12.2.2-0 for the first build, v12.2.2-1 for the next, etc.
function get_next_build_number_for_tag () {
  tag_w_highest_build_number="${1}"
  version_tag="${2}"
  # If there are no tags matching the version, report the next build number is zero
  if [ -z "${tag_w_highest_build_number}" ]; then
    echo '0'
    return
  fi
  # Remove '<version tag>-' from the beginning of the string to get the build number
  build_number="$(extract_build_number "${tag_w_highest_build_number}" "${version_tag}")"
  echo "$((build_number + 1))"
}

MANIFEST_TOOL_VERSION="v0.7.0"
MANIFEST_TOOL_LOCATION="/tmp/manifest-tool-${MANIFEST_TOOL_VERSION}"
# Manifest tool: https://github.com/estesp/manifest-tool
function download_manifest_tool () {
  BUILD_SERVER_GOARCH="amd64"  # We assume below the build server is x86_64 (amd64)
  if [[ ! -x "${TOOL_BINARY_LOCATION}" ]]; then
    info "Manifest tool is not downloaded. Downloading it now."
    curl --silent --location \
      "https://github.com/estesp/manifest-tool/releases/download/${MANIFEST_TOOL_VERSION}/manifest-tool-linux-${BUILD_SERVER_GOARCH}" > "${MANIFEST_TOOL_LOCATION}"
  fi
}

# For a given version of ceph, if there exists both an x86_64 image and an aarch64 image, push a
# manifest image for multi arch support: https://blog.docker.com/2017/11/multi-arch-all-the-things/
function push_manifest_image () {
  ceph_version_tag="${1}"
  amd64_tag="$(get_tag_w_highest_build_number "${ceph_version_tag}" "${AMD64_PUSH_REPOSITORY}")"
  arm64_tag="$(get_tag_w_highest_build_number "${ceph_version_tag}" "${ARM64_PUSH_REPOSITORY}")"
  if [ -z "${amd64_tag}" ]; then
    info "Not pushing manifest image for tag ${ceph_version_tag} because there is no \
x86_64 (amd64) image (${AMD64_PUSH_REPOSITORY}) tagged for this version."
    return 0
  elif [ -z "${arm64_tag}" ]; then
    info "Not pushing manifest image for tag ${ceph_version_tag} because there is no \
aarch64 (arm64) image (${ARM64_PUSH_REPOSITORY}) tagged with this version."
    return 0
  fi
  amd64_build_number="$(extract_build_number "${amd64_tag}" "${ceph_version_tag}")"
  arm64_build_number="$(extract_build_number "${arm64_tag}" "${ceph_version_tag}")"
  # Instead of figuring out what the next number in line is for the manifest image, we can be
  # certain that it is a monotonically increasing unique number if we use the amd build number
  # plus the arm build number, which are also monotonically increasing. The only oddity will be that
  # the build number sometimes increments by 2 if both centos images have updates at the same time.
  manifest_image_build_number="$(( amd64_build_number + arm64_build_number ))"
  manifest_image_tag="$(printf %s-%d "${ceph_version_tag}" "${manifest_image_build_number}")"
  manifest_image_full_tag="${PUSH_REPOSITORY}:${manifest_image_tag}"
  if tag_exists_on_repository "${manifest_image_tag}" "${PUSH_REPOSITORY}"; then
    info "Manifest image ${manifest_image_full_tag} already exists. Not pushing it again."
    return 0
  fi
  # We can't use the commandline template for manifest-tool since we have build numbers.
  # Must create a YAML file for our spec
  manifest_spec_file="/tmp/${manifest_image_full_tag}.yaml"
  cat > "${manifest_spec_file}" <<EOF
image: "${PUSH_LIBRARY}/${manifest_image_full_tag}"
manifests:
  - image: "${PUSH_LIBRARY}/${AMD64_PUSH_REPOSITORY}:${amd64_tag}"
    platform:
      architecture: amd64
      os: linux
  - image: "${PUSH_LIBRARY}/${ARM64_PUSH_REPOSITORY}:${arm64_tag}"
    platform:
      architecture: arm64
      os: linux
EOF
  download_manifest_tool
  echo ${MANIFEST_TOOL_LOCATION} push from-spec "${manifest_spec_file}"
}

function get_base_image_id () {
  image_full_tag="${1}"
  # Docker history gives all the image IDs which built the given image with recent images first
  # The first layers can be ID'ed '<missing>' so filter this out with grep
  # Of the remaining non-missing IDs, the last one should be the base image
  docker history --format '{{.ID}}' "${image_full_tag}" | grep --invert-match '<missing>' | tail -1
}

function get_image_id () {
  image_full_tag="${1}"
  # The last layer in the history is the ID for this image that other images will see as the base ID
  docker history --format '{{.ID}}' "${image_full_tag}" | head -1
}

function do_push () {
  image_full_tag="${1}"
  echo docker push "${PUSH_LIBRARY}/${image_full_tag}"
}

function do_pull () {
  image_full_tag="${1}"
  docker pull "${PUSH_LIBRARY}/${image_full_tag}"
}


#---------------------------------------------------------------------------------------------------
# MAIN, BASICALLY
#---------------------------------------------------------------------------------------------------

for flavor in ${FLAVORS_TO_BUILD}; do
  # shellcheck disable=2206 # quoting to prevent word splitting below breaks conversion to array
  flavor_array=(${flavor//,/ })
  ceph_codename="${flavor_array[0]}"  # e.g., luminous/mimic
  # distro="${flavor_array[1]}"  # Only CentOS is supported
  distro_release="${flavor_array[2]}" # e.g., centos *6*, centos *7*

  #
  # Build amd64/x86_64
  for arch in "x86_64" "aarch64"; do
  ceph_version_list="$(ceph_versions_on_server "${ceph_codename}" "${distro_release}" "${arch}")"
  cat <<EOF

${arch} Ceph ${ceph_codename} packages available:
${ceph_version_list}
EOF
  if [ "${arch}" = "x86_64" ];then
    ceph_container_distro_dir="centos"
    push_image_repo="${AMD64_PUSH_REPOSITORY}"
    centos_container_library="amd64"
  elif [ "${arch}" = "aarch64" ]; then
    ceph_container_distro_dir="centos-arm64"
    push_image_repo="${ARM64_PUSH_REPOSITORY}"
    centos_container_library="arm64v8"  # pull the arm version of centos from arm64v8/centos:7
  fi

    for version in ${ceph_version_list}; do
      version_tag="v${version}"  # e.g. 'v12.2.2'
      last_tag="$(get_tag_w_highest_build_number "${version_tag}" "${push_image_repo}")"
      if [ ! -z "${last_tag}" ]; then
        # If the last tag is not empty, we must compare its base to the latest base
        # Pull the last image and the base image (centos:X) to see if the base images match
        last_image_full_tag="${push_image_repo}:${last_tag}"
        do_pull "${last_image_full_tag}"
        centos_full_tag="${centos_container_library}/centos:${distro_release}"
        do_pull "${centos_full_tag}"
        last_image_base_id="$(get_base_image_id "${last_image_full_tag}")"
        centos_image_id="$(get_image_id "${centos_full_tag}")"
        if [ "${last_image_base_id}" = "${centos_image_id}" ]; then
          # The last ceph image's base ID is the same as the latest centos image's ID
          info "No base container update for Ceph release ${version}-${arch}"
          info "Image will remain at tag ${last_image_full_tag}"
          continue  # Go to the next loop item without building
        else
          info "Base container ${centos_image_id} has an update for Ceph release ${version}-${arch}"
          # Build a new container
        fi
      else
        info "No tag exists matching Ceph release ${version}-${arch}"
        # Build a new container
      fi
      # Build and push our next flavor with our specific Ceph version
      next_build_number="$(get_next_build_number_for_tag "${last_tag}" "${version_tag}")"
      next_tag="$(printf '%s-%d' "${version_tag}" "${next_build_number}")"  # e.g., v12.2.2-4
      next_image_full_tag="${push_image_repo}:${next_tag}"
      info "Building a new image ${next_image_full_tag} for Ceph release ${version}-${arch}"
      make FLAVORS="${ceph_codename}-${version},${ceph_container_distro_dir},${distro_release}" \
            IMAGES_TO_BUILD=daemon-base \
            TAG_REGISTRY="${PUSH_LIBRARY}" \
            DAEMON_BASE_TAG="${next_image_full_tag}" \
            BASEOS_REGISTRY="${centos_container_library}" \
            BASEOS_REPO='centos' \
          build
      do_push "${next_image_full_tag}"
    done  # for version in ${ceph_version_list}
    if [ "${arch}" = "aarch64" ]; then
      # Once we have built an ARM version, try to push a manifest image. We only need to do this
      # once, here after the ARM image. A manifest image will not get pushed (with an INFO message)
      # if an x86_64 (amd64) version does not exist. And if a corresponding ARM version does not
      # exist for a particular x86_64 version, we don't need to try to make a manifest image for
      # that x86_64 one anyway.
      push_manifest_image "${version_tag}"
    fi

  done # for arch in "x86_64" "aarch_64"

done  # for flavor in ${FLAVORS_TO_BUILD}
