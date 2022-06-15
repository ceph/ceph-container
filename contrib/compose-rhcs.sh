#!/bin/bash
set -e


#############
# VARIABLES #
#############

RHEL_VER=${1:-8}
STAGING_DIR=staging/pacific-ubi${RHEL_VER}-latest-x86_64/
DAEMON_DIR=$STAGING_DIR/daemon
DAEMON_BASE_DIR=${DAEMON_DIR}-base/
DOCKERFILE_DAEMON=$DAEMON_DIR/Dockerfile
DOCKERFILE_DAEMON_BASE=$DAEMON_DIR/Dockerfile
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
  for dockerfile in "$DOCKERFILE_DAEMON" "$DOCKERFILE_DAEMON_BASE"; do
    if [ ! -f "$dockerfile" ]; then
      fatal "Missing dockerfile $dockerfile ! Please stage first !"
    fi
  done
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

# Select the end of the daemon Dockerfile to complete the daemon-base's one
merge_content() {
  grep -B1 -A1000 "# Add ceph-container files" $DOCKERFILE_DAEMON >> $COMPOSED_DIR/Dockerfile || fatal "Cannot find starting point in $DOCKERFILE_DAEMON"
}

clean_staging() {
  if [ -d "$STAGING_DIR" ]; then
    rm -rf "${STAGING_DIR:?}"
  fi
}

make_staging() {
  make BASEOS_REGISTRY=registry.redhat.io BASEOS_REPO=ubi${RHEL_VER}/ubi-minimal FLAVORS=pacific,ubi${RHEL_VER},latest || fatal "Cannot build rhel${RHEL_VER}"
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
import_content $DAEMON_DIR
import_content $DAEMON_BASE_DIR
merge_content
success
