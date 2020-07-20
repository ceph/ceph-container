#!/bin/bash
set -euo pipefail

CEPH_VERSION_SPEC=$1
WHAT_TO_EXTRACT=$2

# By default, we consider that CEPH_VERSION_SPEC in this style: luminous
# So no point release, just a version
CEPH_POINT_RELEASE=""
CEPH_VERSION="${CEPH_VERSION_SPEC}"

function parse_ceph_version_spec {
  local version_spec="${1}"
  shift
  # Search for the two possible separators between CEPH_VERSION and CEPH_POINT_RELEASE
  # Let's consider CEPH_VERSION_SPEC=luminous-12.2.0-1
  local ceph_point_release=""
  for separator in "=" "-"; do
    # If the line doesn't have a separator, let's try the next one
    if [[ ! "${version_spec}" =~ ${separator} ]]; then continue; fi

    # If we found it, let's save both parts in the respective variables
    # shellcheck disable=SC2034
    ceph_point_release="${separator}${CEPH_VERSION_SPEC#*${separator}}"
    # Don't continue if we found something
    break
  done
  # Let's print the requested variable
  echo "${ceph_point_release}"
}

function get_ceph_version {
  local release="${1}"
  case  "${release}" in
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
    *)
      echo master
      ;;
  esac
}

# If we pass a dev branch, we don't know the version so let's use the branch name as the ceph version
case "$WHAT_TO_EXTRACT" in
  CEPH_POINT_RELEASE)
    if [[ $CEPH_VERSION =~ ^wip* ]]; then
      echo $CEPH_POINT_RELEASE
    else
      echo $(parse_ceph_version_spec ${CEPH_VERSION_SPEC})
    fi;;
    CEPH_VERSION)
      echo $(get_ceph_version ${CEPH_VERSION_SPEC})
      ;;
esac
