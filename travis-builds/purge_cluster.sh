#!/bin/bash


# FUNCTIONS
function purge_ceph {
  container_count=$(docker ps -q | wc -l)

  if [[ "${container_count}" -gt 0 ]]; then
    docker stop $(docker ps -q) || echo failed to stop containers
  fi

  rm -rf /var/lib/ceph/*
  rm -rf /etc/ceph
}


# MAIN
purge_ceph
