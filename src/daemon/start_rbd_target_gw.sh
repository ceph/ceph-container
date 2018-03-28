#!/bin/bash
set -e

function start_rbd_target_gw {
  get_config
  check_config

  if [ "${CEPH_GET_ADMIN_KEY}" -eq 1 ]; then
    # ensure we have the admin key
    get_admin_key
    check_admin_key
  fi

  ceph_health client.admin /etc/ceph/"$CLUSTER".client.admin.keyring

  log "SUCCESS"
  # start rbd-target-gw
  exec /usr/bin/rbd-target-gw
}
