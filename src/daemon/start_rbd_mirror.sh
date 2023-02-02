#!/bin/bash
set -e

function start_rbd_mirror {
  get_config
  check_config

  if [ "${CEPH_GET_ADMIN_KEY}" -eq 1 ]; then
    # ensure we have the admin key
    get_admin_key
    check_admin_key
  fi

  if [ ! -e "$RBD_MIRROR_KEYRING" ]; then

    if [ ! -e "$RBD_MIRROR_BOOTSTRAP_KEYRING" ]; then
      log "ERROR- $RBD_MIRROR_BOOTSTRAP_KEYRING must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-rbd -o $RBD_MIRROR_BOOTSTRAP_KEYRING'"
      exit 1
    fi

    ceph_health client.bootstrap-rbd-mirror "$RBD_MIRROR_BOOTSTRAP_KEYRING"

    # Generate the rbd mirror key
    ceph "${CLI_OPTS[@]}" --name client.bootstrap-rbd-mirror --keyring "$RBD_MIRROR_BOOTSTRAP_KEYRING" auth get-or-create client.rbd-mirror."${RBD_MIRROR_NAME}" mon 'profile rbd-mirror' osd 'profile rbd' -o "$RBD_MIRROR_KEYRING"
    chown "${CHOWN_OPT[@]}" ceph. "$RBD_MIRROR_KEYRING"
    chmod 0600 "$RBD_MIRROR_KEYRING"
  fi

  log "SUCCESS"
  # start rbd-mirror
  exec /usr/bin/rbd-mirror "${DAEMON_OPTS[@]}" -n client.rbd-mirror."${RBD_MIRROR_NAME}"
}
