#!/bin/bash
set -e

function start_mgr {
  get_config
  check_config

  # Check to see if our MGR has been initialized
  if [ ! -e "$MGR_KEYRING" ]; then
    get_admin_key
    check_admin_key

    # Create ceph-mgr key
    ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" mon 'allow profile mgr' osd 'allow *' mds 'allow *' -o "$MGR_KEYRING"
    chown --verbose ceph. "$MGR_KEYRING"
    chmod 600 "$MGR_KEYRING"

    if [[ "$MGR_DASHBOARD" == 1 ]]; then
      if ! grep -E "\[mgr\]" /etc/ceph/"${CLUSTER}".conf; then
        cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf

[mgr]
mgr_modules = dashboard
ENDHERE
      fi
      ceph "${CLI_OPTS[@]}" config-key put mgr/dashboard/server_addr "$MGR_IP"
    fi
  fi

  log "SUCCESS"
  # start ceph-mgr
  exec /usr/bin/ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}
