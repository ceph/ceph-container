#!/usr/bin/env bash
set -uo pipefail

# Make subshells use '-uo pipefail'
export SHELLOPTS

# As a note, bash functions which return strings do so by echo'ing the result. When the function
# is called like 'var="$(fxn)"', var will get the return string. Trapping on ERR and returning
# the exit code will make the script exit as expected.
trap 'exit $?' ERR

# This is mostly an internal representation of 'FLAVORS_TO_BUILD'.
# These build scripts don't need to have the aarch64 part of the distro specified
# I.e., specifying 'luminous,centos-arm64,7' is not necessary for aarch64 builds; these scripts
#       will do the right build. See configurable CENTOS_AARCH64_FLAVOR_DISTRO below
X86_64_FLAVORS_TO_BUILD="octopus,centos,8 pacific,centos,8"
AARCH64_FLAVORS_TO_BUILD="octopus,centos,8 pacific,centos,8"

# Allow running this script with the env var ARCH='aarch64' to build arm images
# ARCH='x86_64'
# ARCH='aarch64'
: "${ARCH:?must be declared with either x86_64 or aarch64!}"

# Use the ceph library by default
PUSH_LIBRARY="ceph"

# Instead of 'daemon-base', call these images 'ceph' so users don't get these confused with the
# daemon-base and daemon images. This is the registry where manifest images are pushed.
PUSH_REPOSITORY="ceph"

# Manifest images point to the below arch-specific images
X86_64_PUSH_REPOSITORY="${PUSH_REPOSITORY}-amd64"
AARCH64_PUSH_REPOSITORY="${PUSH_REPOSITORY}-arm64"

# Push to the quay.io by default
REGISTRY="quay.io"

# Registry API endpoint URL
PUSH_REGISTRY_URL="https://${REGISTRY}/api/v1"

# The distro part of the ceph-releases/<ceph>/<DISTRO> path for centos' aarch64 build
CENTOS_AARCH64_FLAVOR_DISTRO='centos-arm64'

# This is the arch version of build server
: "${BUILD_SERVER_GOARCH:=amd64}"

#===================================================================================================
# Logging
#===================================================================================================

# ARCH='x86_64'
# ARCH='aarch64'
LOG_FILE="./build-ceph-${ARCH}-$(date +%Y%m%d%H%M%S).log"

# Print info message on stderr and to logfile
function info () {
  local msg="    BUILD CEPH - INFO: ${*}"
  >&2 echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}"
}

# Print error message on stderr and to logfile, then exit with failure
function error () {
  local msg="    BUILD CEPH - ERR : ${*}"
  >&2 echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}"
  return 1
}

dry_run_info () {
  local msg="        BUILD CEPH - DRY : ${*}"
  >&2 echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}"
}

# Print test message on stderr and to logfile
function test_info () {
  local msg="        BUILD CEPH - TEST: ${*}"
  >&2 echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}"
}

echo ''
info "LOGGING TO ${LOG_FILE}"
if [ -n "${TEST_RUN:-}" ]; then
  info "THIS IS A TEST RUN"
  DRY_RUN=true  # test run implies dry run
fi
if [ -n "${DRY_RUN:-}" ]; then
  info "THIS IS A DRY RUN"
fi


#===================================================================================================
# Build flavors and conversion/extraction of flavor details into other useful parts
#   A full tag is a tag including the library, repo and tag '<lib>/<repo>:<tag>'
#     e.g., 'ceph/ceph:v12.2.2-20180517'
#===================================================================================================

function get_flavors_to_build () {
  local arch="${1}"
  if [ "${arch}" = 'x86_64' ]; then
    echo "${X86_64_FLAVORS_TO_BUILD}"
    return
  elif [ "${arch}" = 'aarch64' ]; then
    echo "${AARCH64_FLAVORS_TO_BUILD}"
    return
  fi
  error "get_flavors_to_build - unknown arch '${arch}'"
}

# Given a flavor, return the Ceph codename (e.g., luminous, mimic, ...)
function extract_ceph_codename () {
  local flavor="${1}"
  # shellcheck disable=2206 # quoting to prevent word splitting below breaks conversion to array
  local flavor_array=(${flavor//,/ })
  echo "${flavor_array[0]}"
}

# Given a flavor, extract the distro (e.g., centos)
# These build scripts want the distro without the '-arm64' suffix
function extract_distro () {
  local flavor="${1}"
  # shellcheck disable=2206 # quoting to prevent word splitting below breaks conversion to array
  local flavor_array=(${flavor//,/ })
  local flavor="${flavor_array[1]}"  # e.g., centos
  echo "${flavor%-arm64}"
}

# Given a flavor, extract the distro release (e.g., centos *6*, centos *7*)
function extract_distro_release () {
  local flavor="${1}"
  # shellcheck disable=2206 # quoting to prevent word splitting below breaks conversion to array
  local flavor_array=(${flavor//,/ })
  echo "${flavor_array[2]}"
}

# Return the arch-specific image repo
function get_arch_image_repo () {
  local arch="${1}"
  if [ "${arch}" = 'x86_64' ]; then
    echo "${X86_64_PUSH_REPOSITORY}"
    return
  elif [ "${arch}" = 'aarch64' ]; then
    echo "${AARCH64_PUSH_REPOSITORY}"
    return
  fi
  error "get_arch_image_repo - unknown arch '${arch}'"
}

# Given a flavor and arch, return the full tag of the base image
function get_base_image_full_tag () {
  local flavor="${1}" arch="${2}"
  if [ "${arch}" = 'x86_64' ] || [ "${arch}" = 'aarch64' ]; then
    local default_library="${REGISTRY}/centos"
  else
    error "get_base_image_full_tag - unknown arch '${arch}'"
  fi
  local distro ; distro="$(extract_distro "${flavor}")"
  local distro_release ; distro_release="$(extract_distro_release "${flavor}")"
  case $distro in
    centos)
      echo "${default_library}/centos:${distro_release}"
      return ;;
    *)
      error "get_base_image_full_tag - unknown distro '${distro}'"
  esac
}

# Return the library portion of the image's (full) tag
function get_image_library () {
  local image_full_tag="${1}"
  echo "${image_full_tag%%/*}"
}

# Return the repo portion of the image's (full) tag
function get_image_repo () {
  local image_full_tag="${1}"
  local tag_minus_library="${image_full_tag#*/}"
  echo "${tag_minus_library%:*}"
}

# Return the tag portion of the image's (full) tag
function get_image_tag () {
  image_full_tag="${1}"
  echo "${image_full_tag##*:}"
}

# Given a distro and arch, return the distro part of the "ceph-releases/<release>/<distro>/..."
# path from the ceph-container project. The distro part of the path for centos aarch64 builds is
# 'centos-arm64', for example. This value should be used for the distro part of the flavor specified
# during 'make build'.
# E.g., for centos aarch64, 'make FLAVORS_TO_BUILD=<ceph>,centos-arm64,<centos-rel> ... build'
function get_ceph_container_releases_distro_pathname () {
  local distro="${1}" arch="${2}"
  if [ "${arch}" = 'x86_64' ]; then
    echo "${distro}"  # No special path for x86 images
    return
  elif [ "${arch}" = 'aarch64' ]; then
    case $distro in
      centos)
        echo "${CENTOS_AARCH64_FLAVOR_DISTRO}"  # centos's arm build uses the path centos-amd64
        return ;;
      *)
        error "get_ceph_container_releases_distro_pathname - unknown distro '${distro}'"
    esac
  fi
  error "get_ceph_container_releases_distro_pathname - unknown arch '${arch}'"
}


#===================================================================================================
# Ceph package downloads
#===================================================================================================

# Return the URL where Ceph packages for a flavor+arch can be downloaded
function get_ceph_download_url () {
  local flavor="${1}" arch="${2}"
  local ceph_codename ; ceph_codename="$(extract_ceph_codename "${flavor}")"
  local distro ; distro="$(extract_distro "${flavor}")"
  local distro_release ; distro_release="$(extract_distro_release "${flavor}")"
  case $distro in
    centos)
      local flavor_path="rpm-${ceph_codename}/el${distro_release}"
      ;;
    *)
      error "get_ceph_download_url - unknown distro '${distro}''"
  esac
  echo "https://download.ceph.com/${flavor_path}/${arch}/"
}

# Return a list of the ceph version strings available on the server as:
#   "12.2.0 12.2.1 12.2.2..."
function get_ceph_versions_on_server () {
  local server_url="${1}"
  # Curl gives a listing of the URL like below:
  # <a href="ceph-12.2.7-0.el7.x86_64.rpm">ceph-12.2.7-0.el7.x86_64.rpm</a>  17-Jul-2018 14:11  3024
  # The ceph base package can be id'ed uniquely by the text ">ceph-" followed by a version string
  # Only match stable releases which are identified by the minor number '2'
  local pkg_regex=">ceph-[0-9]+.[2].[0-9]+-[0-9]+"
  # pkg_list is returned in the form ">ceph-12.2.0 >ceph-12.2.1 >ceph-12.2.2 ..."
  local pkg_list
  # Make sure the versions are sorted. This should always be the case, but it's better to be safe.
  pkg_list="$(curl --silent "${server_url}" | grep --extended-regexp --only-matching "${pkg_regex}" | sort --version-sort)"
  local version_list=""  # version strings only
  for pkg in $pkg_list; do
    version_list="${version_list} ${pkg#>ceph-}"  # strip '>ceph-' text from beginning of pkg names
  done
  echo "${version_list}"
}


#===================================================================================================
# Version manipulation
#   A version is a Ceph version in semver form with build number<major>.<minor>.<bug>-<build>
#   A version tag is partly used for tagging images and is in the form 'v<major>.<minor>.<bug>'
#   A version tag build is the version tag with a build version appended
#===================================================================================================

# Given a ceph version, convert it to a version tag
# e.g., 12.2.2-0 becomes 'v12.2.2'
# The 'v' preceding the version is important to the function of these scripts. Searching for a
# version '1.0.0' might also match a version '11.0.0' unless the search is for 'v1.0.0'.
function convert_version_to_version_tag () {
  version="${1}"
  version_minus_build_number="${version%-*}"
  echo "v${version_minus_build_number}"
}


# We use the 8-char date (YYYYMMDD) as the build number to simplify things
function generate_new_build_number () {
  date --utc +%Y%m%d
}

# Given an image repo, version tag, and build number: construct the full tag to push
function construct_full_push_image_tag () {
  local version_tag="${1}" image_repo="${2}" build_number="${3}"
  if [ -z "${build_number}" ]; then
    # If build number is empty string, don't append it
    echo "${REGISTRY}/${PUSH_LIBRARY}/${image_repo}:${version_tag}"
    return
  fi
  echo "${REGISTRY}/${PUSH_LIBRARY}/${image_repo}:${version_tag}-${build_number}"
}

# Given a full tag, extract the build number from it
function extract_full_tag_build_number () {
  local full_tag="${1}"
  echo "${full_tag##*-}"
}

# Return the most recent build number between 2 build numbers
function latest_build_number () {
  printf '%s\n%s' "${1}" "${2}" | sort --version-sort | tail -1
}

# Return the version string with the build number stripped from the end
# Build number is assumed to be <version>-<build-num>,; the hyphen and build-num are both stripped
# build-num itself is assumed not to contain hyphens.
function convert_version_to_version_without_build () {
  local version="${1}"
  echo "${version%-*}"
}

# Convert a version tag to a major-minor-version tag (e.g., v12.2.2 -> v12.2)
function convert_version_tag_to_major_minor_tag () {
  local version_tag="${1}"
  echo "${version_tag%.*}"
}

# Convert a version tag to a major-version tag (e.g., v12.2.2 -> v12)
function convert_version_tag_to_major_tag () {
  local version_tag="${1}"
  echo "${version_tag%%.*}"
}

# Given a version tag, return the minor version number
function extract_minor_version () {
  local version_tag="${1}"
  local major_and_minor="${version_tag%.*}"
  echo "${major_and_minor#*.}"
}


#===================================================================================================
# Image repository querying
#===================================================================================================

# Return the full tags matching a given version tag on the repository
function get_tags_matching () {
  local version_tag="${1}" repository="${2}"
  # DockerHub API limits page_size to 100, so we must loop through the pages
  # It would be super cool if the DockerHub HTTP API had a filter option ...
  local tag_list_url="${PUSH_REGISTRY_URL}/repository/${PUSH_LIBRARY}/${repository}/tag?page_size=100"
  local all_matching_tags=''
  local page=1
  local response
  while response="$(curl --silent --fail --list-only --location \
                      "${tag_list_url}&page=${page}")"; do
    local matching_tags ; matching_tags="$(echo "${response}" | \
              jq -r ".tags[] | select(.name | match(\"${version_tag}\")) | .name")"
    # jq: From the results of the curl, select all images with a name matching the matcher, and then
    # output the name. Exits success w/ empty string if no matches found.
    if [ -n "${matching_tags}" ]; then
      all_matching_tags="$(printf '%s\n%s' "${all_matching_tags}" "${matching_tags}")"
    fi
    if [ "$(echo "${response}" | jq -r .has_additional)" == "false" ]; then
      break
    else
      page=$((page + 1))
    fi
  done
  local full_tags=''
  for tag in $all_matching_tags; do
    full_tags="$(printf '%s\n%s' "${full_tags}" "${REGISTRY}/${PUSH_LIBRARY}/${repository}:${tag}")"
  done
  echo "${full_tags}"
}

# Return the full tag matching a given string. Return the most recent matching version+build.
# Return empty string if no matching tag was found.
function get_latest_tag_matching () {
  local matcher="${1}" repository="${2}"
  local tags_matching ; tags_matching="$(get_tags_matching "${matcher}" "${repository}")"
  echo "${tags_matching}" | sort --version-sort | tail -1
}

# Given a full semver version tag (v<major>.<minor>.<bug>), return the most recent matching tag
function get_latest_full_semver_tag () {
  local full_semver_version_tag="${1}" repository="${2}"
  # For searching full versions, always use 'v<major>.<minor>.<bug>-' including the dash so that a
  # search for 'v1.1.1' doesn't return 'v1.1.11' for example
  if [ -n "${TEST_RUN:-}" ]; then
    local build_num ; build_num="$(generate_new_build_number)"
    build_num=$((build_num - 1))
    if [[ $repository =~ .*amd64.* ]]; then
      build_num=$((build_num - 1))  # Subtract more from build num for amd64 test images
    fi
    local test_tag="${REGISTRY}/${PUSH_LIBRARY}/${repository}:${full_semver_version_tag}-${build_num}"
    test_info "get_latest_full_semver_tag - returning ${test_tag}"
    echo "${test_tag}"
  else
    get_latest_tag_matching "${full_semver_version_tag}-" "${repository}"
  fi
}

# # Given a major (v<major>) or major+minor (v<major>.<minor>) version tag, return the most recent
# # matching tag
# function get_latest_major_or_minor_tag () {
#   major_or_minor_version_tag="${1}" ; repository="${2}"
#   # For searching major/major-minor versions, always use 'v<major>.' or 'v<major>.<minor>.'
#   # including the final dot so that a search for 'v1.1' doesn't return 'v1.11', for example
#   get_latest_tag_matching "${major_or_minor_version_tag}." "${repository}"
# }

# Return 0 if the tag exists on the repository; nonzero otherwise
function full_tag_exists () {
  local full_tag="${1}"
  local tag="${full_tag##*:}"
  local tag_minus_library="${full_tag##*/}"
  local repository="${tag_minus_library%:*}"
  local tag_query_url="${PUSH_REGISTRY_URL}/repository/${PUSH_LIBRARY}/${repository}/tag/${tag}/images"
  if curl --silent --fail --list-only --show-error --location "${tag_query_url}" &> /dev/null ; then
    local retval=$?
  else
    local retval=$?
    info "full_tag_exists - GET from ${tag_query_url} did not succeed - retval: ${retval}"
  fi
  if [ -n "${TEST_RUN:-}" ]; then
    test_info "full_tag_exists - returning that tag ${full_tag} does not exist"
    return 1  # always return that the tag doesn't exist for test runs
  fi
  return "${retval}"
}


#===================================================================================================
# Local image information
#===================================================================================================

# For a given image and its base image, inspect the local pulls of each image to determine if
# the base image has been updated, suggesting that the image should be updated.
# Return 0 if the base image has changed (needs updated), nonzero otherwise
function image_base_changed () {
    local image="${1}"
    local base_image="${2}"
    image_base_line="$(docker history "${image}" | tail -1 | tr -s ' ')"
    base_base_line="$(docker history "${base_image}" | tail -1 | tr -s ' ')"
    [[ "${image_base_line}" != "${base_base_line}" ]]
    # Basically what is going on here is that we are comparing the basest layer of both the image
    # in question and the base image. The main item helping to determine whether the images are the
    # same is the "CREATED BY" column where we expect the "ADD file:<hash>..." lines to match. There
    # is no reason not to also check the rest of the text as well just in case.
}

#===================================================================================================
# Image operations
#===================================================================================================

# Login on the registry
function do_login () {
  if [ -z "${DRY_RUN:-}" ]; then
    docker login -u "${REGISTRY_USERNAME}" -p "${REGISTRY_PASSWORD}" "${REGISTRY}"
  fi
}

# For an image on the local host, given the full tag (lib/repo:tag) of an image, push it
function do_push () {
  local image_library_repo_tag="${1}"
  local push_cmd="docker push ${image_library_repo_tag}"
  if [ -z "${DRY_RUN:-}" ]; then
    ${push_cmd}
  else
    # just echo what we would've executed if this is a dry run
    dry_run_info "${push_cmd}"
  fi
}

# Given the full tag (lib/repo:tag) of an image, pull it
function do_pull () {
  local image_library_repo_tag="${1}"
  if [ -n "${TEST_RUN:-}" ] && [[ "${image_library_repo_tag}" =~ "${PUSH_LIBRARY}"/.* ]]; then
    # For tests, don't try to build images for the ones we build in these scripts
    test_info "do_pull - Not pulling image ${image_library_repo_tag}"
    return
  fi
  docker pull "${image_library_repo_tag}"
}

# Add a tag to an image
function add_tag () {
  local existing_image_full_tag="${1}" full_tag_to_add="${2}"
  info "add_tag - adding tag ${full_tag_to_add} to ${existing_image_full_tag}"
  local tag_cmd="docker tag ${existing_image_full_tag} ${full_tag_to_add}"
  if [ -z "${DRY_RUN:-}" ]; then
    ${tag_cmd}
  else
    # Just echo the make command we would've executed if this is a dry run
    dry_run_info "${tag_cmd}"
  fi
  do_push "${full_tag_to_add}"
}


#===================================================================================================
# Manifests
#===================================================================================================

MANIFEST_TOOL_VERSION="v1.0.3"
MANIFEST_TOOL_LOCATION="/tmp/manifest-tool-${MANIFEST_TOOL_VERSION}"
# Manifest tool: https://github.com/estesp/manifest-tool
# `docker manifest` command exists but is experiemental and not present in all environments;
#   use manifest tool until `docker manifest` is mainline
function download_manifest_tool () {
  if [[ ! -x "${MANIFEST_TOOL_LOCATION}" ]]; then
    info "Manifest tool is not downloaded. Downloading it now."
    curl --silent --location --output "${MANIFEST_TOOL_LOCATION}" \
      "https://github.com/estesp/manifest-tool/releases/download/${MANIFEST_TOOL_VERSION}/manifest-tool-linux-${BUILD_SERVER_GOARCH}"
    chmod +x "${MANIFEST_TOOL_LOCATION}"
  fi
}

# Push a manifest image for multi arch support:
# https://blog.docker.com/2017/11/multi-arch-all-the-things/
# Manifest image points to x86_64 image and aarch64 image
# The calling program is responsible for making sure that both architecture images exist and that
# the manifest image tag will not overwrite an existing tag
function push_manifest_image () {
  local manifest_image_full_tag="${1}" x86_64_image_full_tag="${2}" aarch64_image_full_tag="${3}"
  local additional_tags="${4}"
  # Replace '/' in the tag with '_' for the file
  local manifest_spec_file="/tmp/${manifest_image_full_tag//\//_}.yaml"
  # Start file off by recording the image
  cat > "${manifest_spec_file}" <<EOF
image: "${manifest_image_full_tag}"
EOF
  # Add additional tags if they are specified
  if [ -n "${additional_tags}" ]; then
    # shellcheck disable=2086  # quoting additional_tags below quotes the entire string
    quoted_tags="$(printf '"%s"\n' ${additional_tags})"  # put quotes around each tag
    # shellcheck disable=2116,2086  # disable errors for below line that don't apply to this case
    one_line="$(echo ${quoted_tags})"  # make one line, and remove leading/trailing space
    comma_delimited="${one_line// /, }"  # add comma-space between quoted tags
    cat >> "${manifest_spec_file}" << EOF
tags: [${comma_delimited}]
EOF
  fi
  # Always add manifests
  cat >> "${manifest_spec_file}" <<EOF
manifests:
  - image: "${x86_64_image_full_tag}"
    platform:
      architecture: amd64
      os: linux
  - image: "${aarch64_image_full_tag}"
    platform:
      architecture: arm64
      os: linux
      variant: v8
EOF
  info "manifest file:
$(cat "${manifest_spec_file}")
"
  download_manifest_tool
  local manifest_cmd="${MANIFEST_TOOL_LOCATION} push from-spec ${manifest_spec_file}"
  if [ -z "${DRY_RUN:-}" ]; then
    ${manifest_cmd}
  else
    # just echo what we would've executed if this is a dry run
    dry_run_info "${manifest_cmd}"
  fi
}


#===================================================================================================
# Misc helpers
#===================================================================================================

# Clean the content of the previous run if any
function do_clean {
  make clean.all || true
}

# Return the sorted intersection of 2 single-line, space-delimited lists
function intersect_lists () {
  local list_a="${1}" list_b="${2}"
  # Turn lists into newline-delimited lists, and sort them by version
  local sorted_a ; sorted_a="$(echo "${list_a// /$'\n'}" | sort)"  # comm needs lexicographic sort
  local sorted_b ; sorted_b="$(echo "${list_b// /$'\n'}" | sort)"
  # Use sorted_a and _b as inputs to comm, which effectively returns the intersection of the lists
  intersected="$(comm -12 <(echo "${sorted_a}") <(echo "${sorted_b}"))"
  intersected="${intersected/#$'\n'}"  # remove leading newline
  echo "${intersected%$'\n'}" | sort --version-sort # return sorted w/ trailing newline removed
}

function install_docker {
  # When we DRY_RUN there is no need to install packages
  if [ -n "${DRY_RUN:-}" ]; then
    return
  fi
  sudo apt-get install -y --force-yes docker.io containerd
  sudo systemctl unmask docker
  sudo systemctl start docker || sudo systemctl restart docker
  sudo systemctl status docker
  sudo chgrp "$(whoami)" /var/run/docker.sock
}
