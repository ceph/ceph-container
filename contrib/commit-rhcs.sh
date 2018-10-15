#!/bin/bash
set -e

#############
# VARIABLES #
#############
COMMIT_TEMPLATE="$(mktemp /tmp/commmit-rhcs.XXXXXX)"
CEPH_CONTAINER_DIR="$(mktemp -d /tmp/ceph-container.XXXXXX)"
CURRENT_GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

#############
# FUNCTIONS #
#############
cleanup() {
  rm -f "$COMMIT_TEMPLATE"
  rm -rf "$CEPH_CONTAINER_DIR"
}

step() {
  echo
  echo "########################################################"
  echo "$@"
  echo "########################################################"
}

fatal() {
  echo "FATAL ERROR !"
  echo "########################################################"
  echo "$@"
  echo "########################################################"
  exit 1
}

########
# MAIN #
########
trap cleanup EXIT QUIT INT TERM

step "Updating local repository"
git fetch || fatal 'Cannot fetch the remote repository'
git reset --hard "origin/$CURRENT_GIT_BRANCH" || fatal "Cannot reset the local directory !"
#shellcheck disable=SC2001
DOWNSTREAM_BRANCH_VERSION=$(echo "$CURRENT_GIT_BRANCH" | sed 's/ceph-\(.*\)-rhel.*/\1/g')

step "Cloning ceph-container $DOWNSTREAM_BRANCH_VERSION"
git clone https://github.com/ceph/ceph-container.git -b "stable-$DOWNSTREAM_BRANCH_VERSION" $CEPH_CONTAINER_DIR

step "Composing RHCS"
pushd "$CEPH_CONTAINER_DIR"
  contrib/compose-rhcs.sh
popd > /dev/null

COMPOSED_DIR=$CEPH_CONTAINER_DIR/staging/luminous-rhel7-7-released-x86_64/composed

if [ ! -d "$COMPOSED_DIR" ]; then
  fatal "There is no composed directory. Looks like the build failed !"
fi

DOCKER_FILE="$COMPOSED_DIR/Dockerfile"
if [ ! -e "$DOCKER_FILE" ]; then
  fatal "$DOCKER_FILE must exists !"
fi

step "Updating local tree"
rsync -aH --delete-before "$COMPOSED_DIR"/* .

step "Adding new files"
git add -A

step "Committing changes"
cat >> "$COMMIT_TEMPLATE" << EOF
<TBD>: <TBD> for rhbz#<TBD>

<PLEASE ADD COMMENTS HERE>

Also, since the last update, the following commits were applied.
This is not related to the bz but needed to keep the resync in coherency with upstream.

EOF
COMMITS=$(git diff --staged | grep GIT_COMMIT |cut -d '"' -f 2 | sed -e ':a;N;$!ba;s/\n/../g')
git -C  $CEPH_CONTAINER_DIR log "$COMMITS" --oneline --no-decorate >> "$COMMIT_TEMPLATE"

git commit -st "$COMMIT_TEMPLATE"
