#!/bin/bash
set -e

# Concept from https://github.com/ceph/ceph-docker/issues/247
# The default structure remains identical
# The file you will find in base and daemon are for Ubuntu

# VARIABLES
PREFIX=build
BRANCH_NAME=""
BASEDIR=$(dirname "$0")
LOCAL_BRANCH=$(cd $BASEDIR && git rev-parse --abbrev-ref HEAD)
LINK_MAP=$(mktemp -p /tmp)
DRY_RUN=false
IGNORED_CHANGES="ceph-releases/jewel/fedora/23/*"


# FUNCTIONS
function echo_info {
  echo ""
  echo "**************************************************"
  echo "$1"
  echo "**************************************************"
  echo ""
}

function check_dry_run {
  set +e && echo "$@" | grep -q "\-\-dry-run" && DRY_RUN=true && echo_info "DRY RUN MODE ACTIVATED"
}

function goto_basedir {
  echo_info "JUMPING INTO THE BASE DIRECTORY OF THE SCRIPT"
  TOP_LEVEL=$(cd $BASEDIR && git rev-parse --show-toplevel)
  if [[ "$(pwd)" != "$TOP_LEVEL" ]]; then
    pushd $TOP_LEVEL
  fi
}

function check_git_status {
  if [[ $(git status --porcelain | wc -l) -gt 0 ]]; then
    echo "LOOKS LIKE YOU HAVE LOCAL CHANGES NOT COMMITED:"
    echo ""
    git status --short
    echo ""
    echo ""
    echo "DO YOU REALLY WANT TO CONTINUE?"
    echo "PRESS ENTER TO CONTINUE OR PRESS CTRL C TO BREAK"
    read
  fi
}

function git_update {
  echo_info "FETCHING MASTER LATEST CONTENT"
  git fetch origin
}

function create_new_branch_name {
  set +e
  echo_info "CREATING NEW BRANCH NAME"
  echo $LOCAL_BRANCH | grep -sq "^$PREFIX"
  if [[ $? -eq 0 ]]; then
    echo "Can not build inside a build branch"
    exit 1
  fi
  BRANCH_NAME=$PREFIX-$LOCAL_BRANCH-$1-$2-$3
  set -e
}

function delete_old_branch_tag {
  echo_info "DELETING OLD BRANCH"
  git branch -D $BRANCH_NAME || true
  git tag -d tag-$BRANCH_NAME || true
}

function create_new_branch {
  echo_info "CREATING NEW BRANCH"
  git checkout -b $BRANCH_NAME
}

function copy_files {
  echo_info "COPYING FILES"
  rm -rf base daemon demo
  cp -Lvr ceph-releases/$1/$2/$3/* .
}

function commit_new_changes {
  echo_info "CREATING COMMIT"
  git add base daemon demo
  git commit -s -m "Building $BRANCH_NAME"
}

function tag_new_changes {
  echo_info "TAGGING NEW BRANCH"
  git tag tag-$BRANCH_NAME $(git log --format="%H" -n 1)
}

function push_new_branch {
  echo_info "PUSHING NEW BRANCH"
  git push -f --tags origin $BRANCH_NAME
}

function move_back_to_initial_working_branch {
  echo_info "MOVING BACK TO INITIAL BRANCH"
  git checkout $LOCAL_BRANCH
}

function generate_link_map {
  for file in $(find -type l); do
    link=$(readlink -f $file | awk -F '/' '{print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF}'  | tr ' ' '/' |sort -u);
    original_file=$(echo $file |cut -d '/' -f 3-);
    echo "$original_file|$link" >> $LINK_MAP
  done
}

function find_impacted_file_by_link {
  impacted_links=$(mktemp -p /tmp)
  for file in $todo; do
    grep $file $LINK_MAP | cut -d '|' -f 1 >> $impacted_links
  done
  cat $impacted_links | tr " " "\n" | awk -F '/' '{print $1,"/",$2,"/",$3}' | tr -d " " | sort -u | uniq
  rm -f $impacted_links
}

# MAIN
check_dry_run $@
goto_basedir
git_update
generate_link_map
for tag in $(git tag | grep "^tag-$PREFIX");
do
  sha=$(git log --pretty=format:'%H' $tag~1 -n1)
  impacted_files=$(git diff --name-only $sha..origin/$LOCAL_BRANCH)
  if [[ -n "$impacted_files" ]]; then
    impacted_sort=$(echo $impacted_files | sed "s|$IGNORED_CHANGES||g" | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq)
    if [[ -n "$impacted_sort" ]]; then
      todo="$impacted_sort $todo"
    fi
  fi
done

todo="$todo $(find_impacted_file_by_link)"
rm -f $LINK_MAP


if [[ -z "$(echo $todo | tr -d ' ')" ]]; then
  echo "Nothing to do, go back to work!"
  exit 0
fi
for changes in $(echo $todo | tr " " "\n" | sort -u | uniq);
do
  CEPH_RELEASE=$(echo $changes | awk -F '/' '{print $1}')
  DISTRO=$(echo $changes | awk -F '/' '{print $2}')
  DISTRO_VERSION=$(echo $changes | awk -F '/' '{print $3}')

  if $DRY_RUN; then
    echo "$CEPH_RELEASE $DISTRO $DISTRO_VERSION will be updated"
  else
    create_new_branch_name $CEPH_RELEASE $DISTRO $DISTRO_VERSION
    delete_old_branch_tag
    create_new_branch
    copy_files $CEPH_RELEASE $DISTRO $DISTRO_VERSION
    commit_new_changes
    tag_new_changes
    push_new_branch
    move_back_to_initial_working_branch
  fi
done
popd &> /dev/null
