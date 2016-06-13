#!/bin/bash


# FUNCTIONS
function purge_ceph {
  docker rm -f $(docker ps -a -q)
  rm -rf /var/lib/ceph/*
  rm -rf /etc/ceph
}


# MAIN
purge_ceph
