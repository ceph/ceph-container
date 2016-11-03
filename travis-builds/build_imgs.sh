#!/usr/bin/env bash
set -xe


# FUNCTIONS
# NOTE (leseb): how to choose between directory for multiple change?
# using "head" as a temporary solution
function copy_dirs {
  # if base, daemon and demo exit we are testing a pushed branch and not a PR
  if [[ ! -d daemon && ! -d base && ! -d demo ]]; then
    dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq)
    if [[ "$(echo $dir_to_test | tr " " "\n" | wc -l)" -ne 1 ]]; then
      if [[ "$(echo $dir_to_test | tr " " "\n" | grep "jewel/ubuntu/14.04")" ]]; then
        dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq | grep "jewel/ubuntu/14.04")
      else
        dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq | head -1)
      fi
    fi
    if [[ ! -z "$dir_to_test" ]]; then
      mkdir -p {base,daemon,demo}
      cp -Lrv $dir_to_test/base/* base
      cp -Lrv $dir_to_test/daemon/* daemon
      cp -Lrv $dir_to_test/demo/* demo
    else
      echo "looks like your commit did not bring any changes"
      echo "building jewel ubuntu 14.04 anyway"
      mkdir -p {base,daemon,demo}
      cp -Lrv ceph-releases/jewel/ubuntu/14.04/base/* base
      cp -Lrv ceph-releases/jewel/ubuntu/14.04/daemon/* daemon
      cp -Lrv ceph-releases/jewel/ubuntu/14.04/demo/* demo
    fi
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

function build_demo_img {
  pushd demo
  sed -i 's|FROM .*|FROM base|g' Dockerfile
  docker build -t demo .
  rm -rf demo
  popd
}

# MAIN
copy_dirs
build_base_img
build_daemon_img
build_demo_img
