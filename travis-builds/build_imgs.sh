#!/usr/bin/env bash
set -xe


# FUNCTIONS
# NOTE (leseb): how to choose between directory for multiple change?
# using "head" as a temporary solution
function copy_dirs {
  dir_to_test=$(git show --name-only | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq)
  if [[ $(echo $dir_to_test | tr -d " " | wc -l) -ne 1 ]]; then
    dir_to_test=$(git show --name-only | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq | head -1)
  fi
  if [[ ! -z $dir_to_test ]]; then
    cp -Lrv $dir_to_test/base/* base
    cp -Lrv $dir_to_test/daemon/* daemon
  fi
}

function build_base_img {
  pushd base
  docker build -t base .
  popd
}

function build_daemon_img {
  pushd daemon
  sed -i 's|FROM .*|FROM base|g' Dockerfile
  docker build -t daemon .
  popd
}


# MAIN
copy_dirs
build_base_img
build_daemon_img
