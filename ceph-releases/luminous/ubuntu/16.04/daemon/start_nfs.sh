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

  log "SUCCESS"
  # start ganesha
  /usr/bin/ganesha.nfsd "${GANESHA_OPTIONS[@]}" -L /var/log/ganesha/ganesha.log "${GANESHA_EPOCH}" || return 0
  exec tailf /var/log/ganesha/ganesha.log
}
