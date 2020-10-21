#!/usr/bin/env bash
set -Eeuo pipefail
# -E option is 'errtrace' and is needed for -e to fail properly from subshell failures

# Allow running this script with the env var DRY_RUN="<something>" to do a dry run of the
# script. Dry runs will output commands that they would have executed as info messages.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# shellcheck disable=SC1090  # sourcing from a variable here does indeed work
source "${SCRIPT_DIR}/ceph-build-config.sh"


#
# Main
#

flavors_to_build="$(get_flavors_to_build "${ARCH}")"

install_docker
do_login
do_clean

echo ''
info "BUILDING CEPH-${ARCH} IMAGES FOR FLAVORS:"
info "  ${flavors_to_build}"

for flavor in $flavors_to_build; do
  ceph_codename="$(extract_ceph_codename "${flavor}")"
  distro="$(extract_distro "${flavor}")"
  ceph_container_distro_dir="$(get_ceph_container_releases_distro_pathname "${distro}" "${ARCH}")"
  distro_release="$(extract_distro_release "${flavor}")"
  ceph_download_url="$(get_ceph_download_url "${flavor}" "${ARCH}")"
  ceph_version_list="$(get_ceph_versions_on_server "${ceph_download_url}")"
  echo ''
  info "${ARCH} Ceph ${ceph_codename} packages available:"
  info "   ${ceph_version_list}"
  arch_image_repo="$(get_arch_image_repo "${ARCH}")"
  base_image_full_tag="$(get_base_image_full_tag "${flavor}" "${ARCH}")"

  for version in ${ceph_version_list}; do
    version_tag="$(convert_version_to_version_tag "${version}")"
    latest_server_image_tag="$(get_latest_full_semver_tag "${version_tag}" "${arch_image_repo}")"
    if [ -n "${latest_server_image_tag}" ] && [ -n "${FORCE_BUILD:-}" ]; then
      info "Force build is enabled"
    elif [ -n "${latest_server_image_tag}" ] && [ -z "${FORCE_BUILD:-}" ]; then
      # If the last tag is not empty, we must compare its base to the latest base
      # Pull the last image and the base image to see if the base images match
      do_pull "${latest_server_image_tag}"
      do_pull "${base_image_full_tag}"
      if image_base_changed "${latest_server_image_tag}" "${base_image_full_tag}"; then
        info "Base container ${base_image_full_tag} has an update for Ceph release ${version}-${ARCH}"
        # Build a new container
      else
        # The last ceph image's base ID is the same as the latest centos image's ID
        info "No base container update for Ceph release ${version}-${ARCH}"
        info "Image will remain at tag ${latest_server_image_tag}"
        continue  # Go to the next loop item without building
      fi
    else
      info "No tag exists matching Ceph release ${version}-${ARCH}"
      # Build a new container
    fi
    # Build and push our new flavor with our specific Ceph version
    build_number="$(generate_new_build_number)"
    full_build_tag="$(construct_full_push_image_tag "${version_tag}" \
                                     "${arch_image_repo}" "${build_number}")"
    version_without_build="$(convert_version_to_version_without_build "${version}")"
    baseos_registry_setting="$(get_image_library "${base_image_full_tag}")"
    baseos_repo_setting="$(get_image_repo "${base_image_full_tag}")"
    baseos_tag_setting="$(get_image_tag "${base_image_full_tag}")"
    info "Building a new image ${full_build_tag}"
    make_cmd="make --directory="${SCRIPT_DIR}/.." \
        FLAVORS="${ceph_codename}-${version_without_build},${ceph_container_distro_dir},${distro_release}" \
        IMAGES_TO_BUILD=daemon-base \
        TAG_REGISTRY="" \
        DAEMON_BASE_TAG="${full_build_tag}" \
        BASEOS_REGISTRY="${baseos_registry_setting}" \
        BASEOS_REPO="${baseos_repo_setting}" \
        BASEOS_TAG="${baseos_tag_setting}" \
      build"
    if [ -z "${DRY_RUN:-}" ]; then
      ${make_cmd}
    else
      # Just echo the make command we would've executed if this is a dry run
      dry_run_info "${make_cmd}"
    fi
    do_push "${full_build_tag}"
  done  # for version in ${ceph_version_list}

done  # for flavor in $flavors_to_build
