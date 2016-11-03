#!/bin/bash


# FUNCTIONS
function purge_ceph {
  containers_to_stop=$(docker ps -q)

  if [ "${containers_to_stop}" ]; then
    docker stop ${containers_to_stop} || echo failed to stop containers
  fi

  rm -rf /var/lib/ceph/*
  rm -rf /etc/ceph
}


# MAIN
purge_ceph
