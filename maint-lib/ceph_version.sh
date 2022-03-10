#!/bin/bash
set -euo pipefail

CEPH_VERSION_SPEC=$1
WHAT_TO_EXTRACT=$2

function parse_ceph_version_spec {
  local version_spec="${1}"
  shift
  local ceph_version="${1}"
  shift
  # By default, we consider that CEPH_VERSION_SPEC in this style: luminous
  # So no point release, just a version
  local ceph_ref="${version_spec}"
  local ceph_point_release=""
  # Search for the two possible separators between CEPH_VERSION and CEPH_POINT_RELEASE
  # Let's consider CEPH_VERSION_SPEC=luminous-12.2.0-1
  for separator in "=" "-"; do
    # If the line doesn't have a separator, let's try the next one
    if [[ ! "${version_spec}" =~ ${separator} ]]; then
      continue;
    fi
    ceph_ref="${CEPH_VERSION_SPEC%%"${separator}"*}"
    # only set point_release if spec looks like "<ceph_version>=<point_release>"
    if [[ "$ceph_ref" == "${ceph_version}" ]]; then
      ceph_point_release="${separator}${CEPH_VERSION_SPEC#*"${separator}"}"
    else
      ceph_ref=${version_spec}
    fi
    # Don't continue if we found something
    break
  done
  echo "${ceph_ref}" "${ceph_point_release}"
}

function get_ceph_version {
  local spec="${1}"
  case  "${spec}" in
    *mimic*)
      echo mimic
      ;;
    *nautilus*)
      echo nautilus
      ;;
    *octopus*)
      echo octopus
      ;;
    *pacific*)
      echo pacific
      ;;
    *quincy*)
      echo quincy
      ;;
    *)
      echo master
      ;;
  esac
}

ceph_version=$(get_ceph_version "${CEPH_VERSION_SPEC}")
if [[ "${CEPH_VERSION_SPEC}" =~ wip ]]; then
  ceph_ref=${CEPH_VERSION_SPEC}
  ceph_point_release=""
else
  read -r ceph_ref ceph_point_release <<< \
       "$(parse_ceph_version_spec "${CEPH_VERSION_SPEC}" "${ceph_version}")"
fi

case "$WHAT_TO_EXTRACT" in
  CEPH_VERSION)
    echo "${ceph_version}"
    ;;
  CEPH_REF)
    echo "${ceph_ref}"
    ;;
  CEPH_POINT_RELEASE)
    echo "${ceph_point_release}"
    ;;
esac
