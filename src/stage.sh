#!/usr/bin/env bash
set -euo pipefail

CEPH_VERSION="$1"
BASEOS_NAME="$2"
BASEOS_TAG="$3"

CP_CMD="cp --preserve=all --no-clobber"

function stage_deepest_files () {
  images_base_dir="${1%/}" # remove trailing '/'
  image_dirs="$(find "${images_base_dir}/" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"
  for image_dir in ${image_dirs}; do
    dest_dir="${STAGING_DIR}/${image_dir}"
    mkdir --parents "${dest_dir}" # Create a corresponding image dir in staging
    echo "Populating ${image_dir} staging from ${images_base_dir}/${image_dir}"
    $CP_CMD --recursive "${images_base_dir}/${image_dir}"/. "${dest_dir}"/
  done
}

function stage_shallower_files () {
  images_base_dir="${1%/}" # remove trailing '/'
  # Then for all images that we're staging, copy the files up to the image
  # base but not within the image base
  image_staging_dirs="$(find "${STAGING_DIR}/" -maxdepth 1 -mindepth 1 -type d)"
  override_dir="${images_base_dir}" # start with deepest dir
  while [ ! -z "${override_dir}" ]; do
    echo "Populating all staging images from ${override_dir}"
    find -D exec "${override_dir}/" -depth -maxdepth 1 -type f | \
      while read file; do copy_to_multiple "${file}" "${image_staging_dirs}"; done
    override_dir="$(move_up_path "${override_dir}")"
  done
}

function copy_to_multiple () {
  source_file="$1"
  dest_dirs="$2"
  for dest in $dest_dirs; do
    # echo "  ${source_file} -> ${dest}" # uncomment to debug file addition
    $CP_CMD "${source_file}" "${dest}/"
  done
}

function move_up_path () {
  path="$1"
  if [[ ! "${path}" =~ .*/.* ]]; then return; fi # return empty if no parent
  echo "${path%/*}"
}

echo "Staging ${CEPH_VERSION}/${BASEOS_NAME}/${BASEOS_TAG}"

# (Re)Set staging directory where we will do the build
STAGING_DIR="staging-${CEPH_VERSION}-${BASEOS_NAME}-${BASEOS_TAG}"
rm -rf "${STAGING_DIR:?}/"
mkdir "${STAGING_DIR}"

# File depth corresponds to specificity, so deeper files are more specific
# Move from more specific to less specific

stage_deepest_files "${CEPH_VERSION}/${BASEOS_NAME}/${BASEOS_TAG}"
stage_deepest_files "core"

stage_shallower_files "${CEPH_VERSION}/${BASEOS_NAME}/${BASEOS_TAG}"
stage_shallower_files "core"

# Do replacements on files
for path in "${STAGING_DIR}"/* ; do
  if [ ! -d "${path}" ]; then continue ; fi
  ./replace.py "${path}"/Dockerfile
  mv "${path}"/Dockerfile "${path}"/Dockerfile.bak
  mv "${path}"/Dockerfile.new "${path}"/Dockerfile
done
