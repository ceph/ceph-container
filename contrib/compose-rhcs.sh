#!/bin/bash
set -e


#############
# VARIABLES #
#############

EL=${RHEL_VERSION:-8}
CEPH_VERSION=${CEPH_VERSION:-main}
STAGING_DIR=staging/"${CEPH_VERSION}"-ubi${EL}-minimal-latest-x86_64/
DAEMON_BASE_DIR=$STAGING_DIR/daemon-base/
DOCKERFILE_DAEMON_BASE=$DAEMON_BASE_DIR/Dockerfile
COMPOSED_DIR=$STAGING_DIR/composed


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
  mkdir -p $COMPOSED_DIR
}

import_content() {
  rsync -a --exclude "__*__" --exclude "*.bak" --exclude "*.md" "$1"/* $COMPOSED_DIR/ || fatal "Cannot rsync"
}

clean_staging() {
  if [ -d "$STAGING_DIR" ]; then
    rm -rf "${STAGING_DIR:?}"
  fi
}

make_staging() {
  make BASEOS_REGISTRY=registry.redhat.io BASEOS_REPO=ubi"${EL}"/ubi-minimal FLAVORS="${CEPH_VERSION}",ubi"${EL}"-minimal,latest IMAGES_TO_BUILD=daemon-base || fatal "Cannot build rhel${EL}"
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
import_content $DAEMON_BASE_DIR
success
