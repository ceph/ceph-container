#!/bin/bash
set -e

function start_rbd_mirror {
  get_config
  check_config
  create_socket_dir

  # ensure we have the admin key
  get_admin_key
  check_admin_key

  log "SUCCESS"
  # start rbd-mirror
  exec /usr/bin/rbd-mirror ${CEPH_OPTS} -d --setuser ceph --setgroup ceph
}
