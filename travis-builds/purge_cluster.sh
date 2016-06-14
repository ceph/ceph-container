#!/bin/bash


# FUNCTIONS
function purge_ceph {
  docker stop $(docker ps -q)
  rm -rf /var/lib/ceph/*
  rm -rf /etc/ceph
}


# MAIN
purge_ceph
