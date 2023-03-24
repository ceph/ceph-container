#!/bin/bash
set -e

source "$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/common.sh"

#############
# VARIABLES #
#############

if [[ -z "${VERSION}" ]]; then
  echo "ERROR: VERSION must be set (eg: VERSION=5)"
  exit 1
fi

UBI=ubi"${UBI_VERSION}-${UBI_BRANDING}"
STAGING_DIR=staging/"${CEPH_RELEASE}"-"${UBI}"-latest-x86_64/
DAEMON_DIR=$STAGING_DIR/daemon
DAEMON_BASE_DIR=$STAGING_DIR/daemon-base/
DOCKERFILE_DAEMON=$DAEMON_DIR/Dockerfile
DOCKERFILE_DAEMON_BASE=$DAEMON_BASE_DIR/Dockerfile
COMPOSED_DIR="${STAGING_DIR}"composed


#############
# FUNCTIONS #
#############

fatal() {
  echo "FATAL ERROR !"
  echo "########################################################"
  echo "$@"
  echo "########################################################"
  exit 1
}

check_staging_exist(){
  if [ ! -f "$DOCKERFILE_DAEMON_BASE" ]; then
    fatal "Missing dockerfile $DOCKERFILE_DAEMON_BASE ! Please stage first !"
  fi
}

create_compose_directory() {
  if [ -d "$COMPOSED_DIR" ]; then
    rm -rf "${COMPOSED_DIR:?}"
  fi
  mkdir -p "$COMPOSED_DIR"
}

import_content() {
  rsync -a --exclude "__*__" --exclude "*.bak" --exclude "*.md" "$1"/* "$COMPOSED_DIR"/ || fatal "Cannot rsync"
}

# Select the end of the daemon Dockerfile to complete the daemon-base's one
merge_content() {
  grep -B1 -A1000 "# Add ceph-container files" "$DOCKERFILE_DAEMON" >> "$COMPOSED_DIR"/Dockerfile || fatal "Cannot find starting point in $DOCKERFILE_DAEMON"
}

clean_staging() {
  if [ -d "$STAGING_DIR" ]; then
    rm -rf "${STAGING_DIR:?}"
  fi
}

make_staging() {
  make BASEOS_REGISTRY=registry.redhat.io BASEOS_REPO="ubi${UBI_VERSION}"/ubi-minimal FLAVORS="${CEPH_RELEASE}","${UBI}",latest || fatal "Cannot build ${UBI}"
}

success() {
  echo "###########################################################################################"
  echo "Composed RHCS directory is available at $COMPOSED_DIR"
  echo "###########################################################################################"
}


########
# MAIN #
########

clean_staging
make_staging
check_staging_exist
create_compose_directory
if [[ "${VERSION}" == "5" ]]; then
  import_content "$DAEMON_DIR"
fi
import_content "$DAEMON_BASE_DIR"
if [[ "${VERSION}" == "5" ]]; then
  merge_content
fi
success
