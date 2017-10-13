#!/bin/bash


# FUNCTIONS
function purge_ceph {
  containers_to_stop=$(sudo docker ps -q)

  if [ "${containers_to_stop}" ]; then
    sudo docker stop ${containers_to_stop} || echo failed to stop containers
  fi

  sudo rm -rf /var/lib/ceph/*
  sudo rm -rf /etc/ceph
}


# MAIN
purge_ceph
