#!/bin/bash
set -e

function start_rpc {
  rpcbind || return 0
  rpc.statd -L || return 0
  rpc.idmapd || return 0

}

function start_nfs {
  get_config
  check_config

  # Init RPC
  start_rpc

  if [ ! -e "$RGW_KEYRING" ]; then

    if [ ! -e "$RGW_BOOTSTRAP_KEYRING" ]; then
      log "ERROR- $RGW_BOOTSTRAP_KEYRING must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-rgw -o $RGW_BOOTSTRAP_KEYRING'"
      exit 1
    fi

    ceph_health client.bootstrap-rgw "$RGW_BOOTSTRAP_KEYRING"

    # Generate the RGW key
    ceph "${CLI_OPTS[@]}" --name client.bootstrap-rgw --keyring "$RGW_BOOTSTRAP_KEYRING" auth get-or-create client.rgw."${RGW_NAME}" osd 'allow rwx' mon 'allow rw' -o "$RGW_KEYRING"
    chown "${CHOWN_OPT[@]}" ceph. "$RGW_KEYRING"
    chmod 0600 "$RGW_KEYRING"
  fi

  # create ganesha log directory since the package does not create it
  mkdir -p /var/log/ganesha/ /var/run/ganesha

  log "SUCCESS"
  # start ganesha, logging both to STDOUT and to the configured location
  exec /usr/bin/ganesha.nfsd "${GANESHA_OPTIONS[@]}" -F -L STDOUT "${GANESHA_EPOCH}"
}
