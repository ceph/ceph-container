#!/bin/bash
set -euo pipefail

CEPH_VERSION_SPEC=$1
WHAT_TO_EXTRACT=$2

# By default, we consider that CEPH_VERSION_SPEC in this style: luminous
# So no point release, just a version
CEPH_POINT_RELEASE=""
CEPH_VERSION="${CEPH_VERSION_SPEC}"

# If we pass a dev branch, we don't know the version so let's use the branch name as the ceph version
if [[ $WHAT_TO_EXTRACT == "CEPH_POINT_RELEASE" ]]; then
  if [[ $CEPH_VERSION =~ ^wip* ]]; then
    echo $CEPH_POINT_RELEASE
    exit 0
  fi
else
  if [[ $CEPH_VERSION =~ ^wip* ]]; then
    echo "$CEPH_VERSION"
    exit 0
  fi
fi

# Search for the two possible separators between CEPH_VERSION and CEPH_POINT_RELEASE
# Let's consider CEPH_VERSION_SPEC=luminous-12.2.0-1
for separator in "=" "-"; do
  # If the line doesn't have a separator, let's try the next one
  if [[ ! "${CEPH_VERSION_SPEC}" =~ ${separator} ]]; then continue; fi

  # If we found it, let's save both parts in the respective variables
  # shellcheck disable=SC2034
  CEPH_VERSION="${CEPH_VERSION_SPEC%%${separator}*}"
  # shellcheck disable=SC2034
  CEPH_POINT_RELEASE="${separator}${CEPH_VERSION_SPEC#*${separator}}"

  # Don't continue if we found something, it's time to print it
  break
done

# Let's print the requested variable
echo "${!WHAT_TO_EXTRACT}"
