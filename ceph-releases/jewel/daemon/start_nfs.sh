#!/bin/bash
set -e

function start_nfs {
  echo "Temporarily disabled due to broken package dependencies with nfs-ganesha"
  echo "For more info see: https://github.com/ceph/ceph-docker/pull/564"
  exit 1
}
