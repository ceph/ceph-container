#!/bin/bash
set -e

function start_mgr {
  get_config
  check_config

  # ensure we have the admin key
  get_admin_key
  check_admin_key

  # Check to see if our MGR has been initialized
  if [ ! -e "$MGR_KEYRING" ]; then
    # Create ceph-mgr key
    ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" mon 'allow profile mgr' osd 'allow *' mds 'allow *' -o "$MGR_KEYRING"
    chown --verbose ceph. "$MGR_KEYRING"
    chmod 600 "$MGR_KEYRING"
  fi

  if [[ "$MGR_DASHBOARD" == 1 ]]; then
    ceph "${CLI_OPTS[@]}" mgr module enable dashboard --force
    ceph "${CLI_OPTS[@]}" config-key put mgr/dashboard/server_addr "$MGR_IP"
    ceph "${CLI_OPTS[@]}" config-key put mgr/dashboard/server_port "$MGR_PORT"
  fi

  log "SUCCESS"
  # start ceph-mgr
  exec /usr/bin/ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}
