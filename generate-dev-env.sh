#!/bin/bash
set -e

# This script generates a dev env for developers
# How to use: ./generate-dev-env.sh $CEPH_RELEASE $DISTRO $DISTRO_VERSION

# VARIABLES
BASEDIR=$(dirname "$0")

# FUNCTIONS
function echo_info {
  echo ""
  echo "**********************************************************"
  echo -e "$1"
  echo "**********************************************************"
}

function goto_basedir {
  echo_info "JUMPING INTO THE BASE DIRECTORY OF THE SCRIPT"
  TOP_LEVEL=$(cd $BASEDIR && git rev-parse --show-toplevel)
  if [[ "$(pwd)" != "$TOP_LEVEL" ]]; then
    pushd $TOP_LEVEL
  fi
}

function test_args {
  if [ $# -ne 3 ]; then
    echo_info "Please run the script like this: ./generate-dev-env.sh CEPH_RELEASE DISTRO DISTRO_VERSION"
    exit 1
  fi
}

function copy_files {
  dir=ceph-releases/$1/$2/$3/
  rm -rf $BASEDIR/{base,daemon,demo}
  for file in $(find -L $dir* -type f ); do
    file_dir=$(dirname $file |sed -e "s|$dir||g")
    orig_file=$(readlink -f $file)
    echo "linking $orig_file in $file_dir/"
    mkdir -p $file_dir
    ln $orig_file $file_dir/
  done
  echo ${dir} > base/SOURCE_TREE
  echo ${dir} > daemon/SOURCE_TREE
  echo ${dir} > demo/SOURCE_TREE
}

function test_combination {
  stat ceph-releases/$1/$2/$3/ &> /dev/null || wrong_combination
}

function wrong_combination {
  echo_info "Incompatible combination of CEPH_RELEASE, DISTRO and DISTRO_VERSION \n
  If you want to bring the support of a new Ceph release, \n
  create the necessary dir/files in ceph-releases and THEN execute this script"
  exit 1
}


# MAIN

goto_basedir
test_args $@

case "$1" in
  hammer|infernalis|jewel)
    case "$2" in
      centos|ubuntu|fedora)
          test_combination $@
          copy_files $@
        ;;
      *)
        wrong_combination
      esac
    ;;
esac
popd &> /dev/null
