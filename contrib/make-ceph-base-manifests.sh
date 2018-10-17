#!/usr/bin/env bash
set -euo pipefail

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

  # We are going to note the last version we see of a particular minor version for later use tagging
  # most recent minor images for this major version
  latest_minor_version_tags_list=''

  last_minor_number=0
  last_version_tag=''
  for version in ${paired_versions}; do
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
    if ! full_tag_exists "${manifest_image_tag}"; then
      # If the image doesn't exist in the repo, push it
      push_manifest_image "${manifest_image_tag}" \
        "${x86_latest_server_image_tag}" "${arm_latest_server_image_tag}"
    fi
    # Don't push the image if it does exist

    # Record latest minor versions except for images which are skipped
    minor_number="$(extract_minor_version "${version_tag}")"
    if [ "${minor_number}" -gt "${last_minor_number}" ] && [ -n "${last_version_tag}" ]; then
      # If our minor number has gone up since last time, the last version tag is the latest image
      # for that minor version. Record it.
      latest_minor_version_tags_list="${latest_minor_version_tags_list} ${last_version_tag}"
    fi
    last_version_tag="${version_tag}"
    last_minor_number="${minor_number}"

  done  # for version in ${paired_versions}

  # Record latest minor version finally outside the loop since the most recent version tag is also
  # the most recent tag for a minor version
  if [ -n "${last_version_tag}" ]; then
    # Once we finish looping over versions, the most recent value in 'last_version_tag' is the
    # latest image for its minor version. Record it.
    latest_minor_version_tags_list="${latest_minor_version_tags_list} ${last_version_tag}"
  fi

  # Tag each of the most recent minor images for this flavor with minor version tag
  # in form 'v<major>.<minor>'
  full_minor_tag=''  # use later for major tag
  latest_server_image_tag=''  # use later for major tag
  for full_minor_tag in $latest_minor_version_tags_list; do
    minor_version_tag="$(convert_version_tag_to_major_minor_tag "${full_minor_tag}")"
    latest_server_image_tag="$(get_latest_full_semver_tag \
                                 "${full_minor_tag}" "${PUSH_REPOSITORY}")"
    minor_push_image_tag="$(construct_full_push_image_tag "${minor_version_tag}" \
                              "${PUSH_REPOSITORY}" '')"   # No build number for minor tag
    if [ -z "${latest_server_image_tag}" ]; then
      info "No manifest image to apply ${minor_push_image_tag} to"
    else
      add_tag "${latest_server_image_tag}" "${minor_push_image_tag}"
    fi
  done

  # The last image we apply a minor version tag to should be the image that we apply a major version
  # tag to in the form 'v<major>'; in other words, the latest image for the highest minor version
  # is also the latest image for the major version of the flavor
  major_version_tag="$(convert_version_tag_to_major_tag "${full_minor_tag}")"
  major_push_image_tag="$(construct_full_push_image_tag "${major_version_tag}" \
                            "${PUSH_REPOSITORY}" '')"   # No build num for major tag
  if [ -z "${latest_server_image_tag}" ]; then
    info "No manifest image to apply ${major_push_image_tag} to"
  else
    add_tag "${latest_server_image_tag}" "${major_push_image_tag}"
  fi

done  # for flavor in $flavors_to_build
