#!/bin/bash

# shellcheck disable=SC2034
UBI_BRANDING=${BRANDING:-ibm}

case "${VERSION}" in
  *4*)
    UBI_VERSION=8
    CEPH_RELEASE=nautilus
    ;;
  *5*)
    UBI_VERSION=8
    CEPH_RELEASE=pacific
    ;;
  *6*)
    UBI_VERSION=9
    CEPH_RELEASE=quincy
    ;;
    *)
    echo "ERROR: VERSION must be set to 4, 5, or 6."
    exit 1
esac

