#!/bin/bash

BRANCH_NAME=""
BASEDIR=$(dirname "$0")
LOCAL_BRANCH=$(cd "$BASEDIR" && git rev-parse --abbrev-ref HEAD)
: "${PREFIX:=build}"

function test_args {
  if [ $# -ne 3 ]; then
    echo_info "Please run the script like this: ./script.sh CEPH_RELEASE DISTRO DISTRO_VERSION"
    exit 1
  fi
}

function echo_info {
  echo ""
  echo "**************************************************"
  echo "$1"
  echo "**************************************************"
  echo ""
}

function move_back_to_initial_working_branch {
  echo_info "MOVING BACK TO INITIAL BRANCH"
  git checkout "$LOCAL_BRANCH"
}

function create_new_branch_name {
  echo_info "CREATING NEW BRANCH NAME"
  BRANCH_NAME=$PREFIX-$LOCAL_BRANCH-$1-$2-$3
}

function delete_old_branch_tag {
  echo_info "DELETING OLD BRANCH"
  git branch -D "$BRANCH_NAME" || true
  git tag -d tag-"$BRANCH_NAME" || true
}

function create_new_branch {
  echo_info "CREATING NEW BRANCH"
  git checkout -b "$BRANCH_NAME"
}

function copy_files {
  echo_info "COPYING FILES"
  rm -rf base daemon demo
  if ! echo "$2" | grep -sq redhat; then
    cp -Lvr ceph-releases/"$1"/"$2"/"$3"/* .
  fi
}

function commit_new_changes {
  echo_info "CREATING COMMIT"
  if [[ ! -d base ]] || [ ! -d demo ]; then
    mkdir base demo
    echo "workaround for kraken and above, do not care about me" > base/README.md
    echo "workaround for kraken and above, do not care about me" > demo/README.md
  fi
  git add base daemon demo
  git commit -s -m "Building $BRANCH_NAME"
}

function tag_new_changes {
  echo_info "TAGGING NEW BRANCH"
  git tag tag-"$BRANCH_NAME" "$(git log --format="%H" -n 1)"
}

function push_new_branch {
  echo_info "PUSHING NEW BRANCH"
  git push -f --tags origin "$BRANCH_NAME"
}

function trigger_build {
  curl -H "Content-Type: application/json" --data '{"source_type": "Tag", "source_name": "$tag-"$BRANCH_NAME"}' -X POST https://registry.hub.docker.com/u/ceph/daemon/trigger/71c59f12-72d9-4d50-a69d-5bd186e6b3a6/
}

CEPH_RELEASE=$1
DISTRO=$2
DISTRO_VERSION=$3

test_args "$@"
create_new_branch_name "$CEPH_RELEASE" "$DISTRO" "$DISTRO_VERSION"
delete_old_branch_tag
create_new_branch
copy_files "$CEPH_RELEASE" "$DISTRO" "$DISTRO_VERSION"
commit_new_changes
tag_new_changes
push_new_branch
move_back_to_initial_working_branch
