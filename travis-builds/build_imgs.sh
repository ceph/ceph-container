#!/usr/bin/env bash
set -xe


# FUNCTIONS
# NOTE (leseb): how to choose between directory for multiple change?
# using "head" as a temporary solution
function copy_dirs {
  # Are we testing a pull request?
  if [[ ( -d daemon || -d base) && -d demo ]]; then
    # We are running on a pushed "release" branch, not a PR. Do nothing here.
    return 0
  fi
  # We are testing a PR. Copy the directories.
  dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq)
  if [[ "$(echo $dir_to_test | tr " " "\n" | wc -l)" -ne 1 ]]; then
    if [[ "$(echo $dir_to_test | tr " " "\n" | grep "kraken/ubuntu/16.04")" ]]; then
      dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq | grep "kraken/ubuntu/16.04")
    else
      dir_to_test=$(git diff --name-only HEAD~1 | tr " " "\n" | awk -F '/' '/ceph-releases/ {print $1,"/",$2,"/",$3,"/",$4}' | tr -d " " | sort -u | uniq | head -1)
    fi
  fi
  if [[ ! -z "$dir_to_test" ]]; then
    mkdir -p {base,daemon,demo}
    cp -Lrv $dir_to_test/base/* base || true
    cp -Lrv $dir_to_test/daemon/* daemon
    cp -Lrv $dir_to_test/demo/* demo || true # on Luminous demo has merged with daemon
  else
    echo "looks like your commit did not bring any changes"
    echo "building Luminous on Ubuntu 16.04"
    mkdir -p {daemon,demo}
    cp -Lrv ceph-releases/luminous/ubuntu/16.04/daemon/* daemon
  fi
}

function build_base_img {
if [[ -d base ]] && [[ "$(find base -type f | wc -l)" -gt 1 ]]; then
    pushd base
    sudo docker build -t base .
    popd
    rm -rf base
  fi
}

function build_daemon_img {
  pushd daemon
  if grep "FROM ceph/base" Dockerfile; then
    sed -i 's|FROM .*|FROM base|g' Dockerfile
  fi
  sudo docker build -t ceph/daemon .
  popd
  rm -rf daemon
}

function build_demo_img {
  if [[ -d demo ]] && [[ "$(find demo -type f | wc -l)" -gt 1 ]]; then
    pushd demo
    if grep "FROM ceph/base" Dockerfile; then
      sed -i 's|FROM .*|FROM base|g' Dockerfile
    fi
  popd
  rm -rf demo
  fi
}

# MAIN
copy_dirs
build_base_img
build_daemon_img
build_demo_img
