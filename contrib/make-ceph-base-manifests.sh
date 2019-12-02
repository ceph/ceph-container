#!/usr/bin/env bash
set -Eeuo pipefail
# -E option is 'errtrace' and is needed for -e to fail properly from subshell failures

# Allow running this script with the env var DRY_RUN="<something>" to do a dry run of the
# script. Dry runs will output commands that they would have executed as info messages.

# This isn't an architecture, so call this 'manifests' for the log file
# shellcheck disable=SC2034  # ARCH is used by the build config include
ARCH='manifests'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# shellcheck disable=SC1090  # sourcing from a variable here does indeed work
source "${SCRIPT_DIR}/ceph-build-config.sh"


#
# Main
#

# For ceph-versioned images with both x86_64 (x86) an aarch64 (arm) images built, make a manifest
# image that points to both.

# Make an assumption that if we build an arm version of a flavor, we also build an x86 version.
# Because we don't make manifests for images without both x86 and arm variants, and because an arm
# flavor implies an x86 flavor is also built, we only need to start here with arm flavors.
flavors_to_build="$(get_flavors_to_build 'aarch64')"

echo ''
info "BUILDING CEPH IMAGE MANIFESTS AND TAGS FOR FLAVORS:"
info "  ${flavors_to_build}"

for flavor in $flavors_to_build; do
  echo ''
  x86_download_url="$(get_ceph_download_url "${flavor}" 'x86_64')"
  arm_download_url="$(get_ceph_download_url "${flavor}" 'aarch64')"
  x86_version_list="$(get_ceph_versions_on_server "${x86_download_url}")"
  arm_version_list="$(get_ceph_versions_on_server "${arm_download_url}")"
  # The intersection will return versions numbers with both x86 and arm builds available
  paired_versions="$(intersect_lists "${x86_version_list}" "${arm_version_list}")"

  # We want to loop through the versions with lookahead to the next version so we know when to apply
  # minor tags to the current version.
  # 1st in paired list is the first version we look at
  version="$(echo "${paired_versions}" | head -1)"  # first line in paired_versions
  # build list of next versions
  next_versions="$(echo "${paired_versions}" | tail -n +2)"  # remove first line in paired_versions
  next_versions="${next_versions}
done"  # add 'done' to end of next_versions list so for loop will continue one past the last version

  for next_version in ${next_versions}; do
    version_tag="$(convert_version_to_version_tag "${version}")"

    x86_arch_image_repo="$(get_arch_image_repo 'x86_64')"
    arm_arch_image_repo="$(get_arch_image_repo 'aarch64')"

    x86_latest_server_image_tag="$(get_latest_full_semver_tag \
                                     "${version_tag}" "${x86_arch_image_repo}")"
    arm_latest_server_image_tag="$(get_latest_full_semver_tag \
                                  "${version_tag}" "${arm_arch_image_repo}")"
    if [ -z "${x86_latest_server_image_tag}" ]; then
      info "Skipping manifest creation for Ceph release ${version}"
      info "  because an x86_64 image does not exist in the image repo."
      continue  # skip manifest creation
    elif [ -z  "${arm_latest_server_image_tag}" ]; then
      info "Skipping manifest creation for Ceph release ${version}"
      info "  because an aarch64 image does not exist in the image repo."
      continue  # skip manifest creation
    fi

    # Push a manifest image that points to both x86 and arm images
    # The build number for the manifest image should be the most recent between the 2 images
    x86_build_number="$(extract_full_tag_build_number "${x86_latest_server_image_tag}")"
    arm_build_number="$(extract_full_tag_build_number "${arm_latest_server_image_tag}")"
    newest_build_number="$(latest_build_number "${x86_build_number}" "${arm_build_number}")"
    manifest_image_tag="$(construct_full_push_image_tag "${version_tag}" \
                                       "${PUSH_REPOSITORY}" "${newest_build_number}")"

    # Apply tags for the minor versions (and major version)
    additional_tags=("${version_tag}")
    minor_number="$(extract_minor_version "${version_tag}")"
    next_minor_number=''
    if [ "${next_version}" == "done" ]; then
      # If the version is the last version, we should apply major tags to this manifest
      additional_tags+=("$(convert_version_tag_to_major_tag "${version_tag}")")
      # leave next minor number as empty
    else
      next_version_tag="$(convert_version_to_version_tag "${next_version}")"
      next_minor_number="$(extract_minor_version "${next_version_tag}")"
    fi
    if [ -z "${next_minor_number}" ] || [ "${next_minor_number}" -gt "${minor_number}" ]; then
      # If there is not next minor number (i.e., this is the last version) or if the next minor
      # number is higher, apply minor tag to this manifest
      additional_tags+=("$(convert_version_tag_to_major_minor_tag "${version_tag}")")
    fi

    if ! full_tag_exists "${manifest_image_tag}" || [ -n "${FORCE_MANIFEST_CREATION:-}" ]; then
      # If the image doesn't exist in the repo, push it
      push_manifest_image "${manifest_image_tag}" \
        "${x86_latest_server_image_tag}" "${arm_latest_server_image_tag}" "${additional_tags[*]:-}"
    fi
    # Don't push the image if it already exists

    version="${next_version}"
  done  # for version in ${paired_versions}

done  # for flavor in $flavors_to_build
