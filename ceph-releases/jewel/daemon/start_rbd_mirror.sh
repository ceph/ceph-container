#!/bin/bash
set -e

function start_rbd_mirror {
  get_config
  check_config

  # ensure we have the admin key
  get_admin_key
  check_admin_key

  log "SUCCESS"
  # start rbd-mirror
  exec /usr/bin/rbd-mirror "${DAEMON_OPTS[@]}"
}
