#!/usr/bin/env bash
set -xe


# FUNCTIONS
# NOTE (leseb): how to choose between directory for multiple change?
# using "head" as a temporary solution
function copy_dirs {
  dir_to_test=$(git diff HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $2,"/",$3,"/",$4,"/",$5}' | tr -d " " | sort -u | uniq)
  if [[ "$(echo $dir_to_test | tr " " "\n" | wc -l)" -ne 1 ]]; then
    if [[ "$(echo $dir_to_test | tr " " "\n" | grep "jewel/ubuntu/14.04")" ]]; then
      dir_to_test=$(git diff HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $2,"/",$3,"/",$4,"/",$5}' | tr -d " " | sort -u | uniq | grep "jewel/ubuntu/14.04")
    else
      dir_to_test=$(git diff HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $2,"/",$3,"/",$4,"/",$5}' | tr -d " " | sort -u | uniq | head -1)
    fi
  fi
  if [[ ! -z "$dir_to_test" ]]; then
    mkdir -p {base,daemon}
    cp -Lrv $dir_to_test/base/* base
    cp -Lrv $dir_to_test/daemon/* daemon
  else
   echo "looks like your commit did not bring any changes"
   echo "building jewel ubuntu 14.04 anyway"
    mkdir -p {base,daemon}
    cp -Lrv ceph-releases/jewel/ubuntu/14.04/base/* base
    cp -Lrv ceph-releases/jewel/ubuntu/14.04/daemon/* daemon
  fi
}

function build_base_img {
  pushd base
  docker build -t base .
  rm -rf base
  popd
}

function build_daemon_img {
  pushd daemon
  sed -i 's|FROM .*|FROM base|g' Dockerfile
  docker build -t daemon .
  rm -rf daemon
  popd
}


# MAIN
copy_dirs
build_base_img
build_daemon_img
