#!/bin/bash
set -e

function kv {
  # Note the 'cas' command puts a value in the KV store if it is empty
  KEY="$1"
  shift
  VALUE="$*"
  log "adding key ${KEY} with value ${VALUE} to KV store"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} cas ${CLUSTER_PATH}"${KEY}" "${VALUE}" || log "value is already set"
}

function populate_kv {
    CLUSTER_PATH=ceph-config/${CLUSTER}
    case "$KV_TYPE" in
       etcd|consul)
          # if ceph.defaults found in /etc/ceph/ use that
          if [[ -e "/etc/ceph/ceph.defaults" ]]; then
            DEFAULTS_PATH="/etc/ceph/ceph.defaults"
          else
          # else use defaults
            DEFAULTS_PATH="/ceph.defaults"
          fi
          # read defaults file, grab line with key<space>value without comment #
          cat "$DEFAULTS_PATH" | grep '^.* .*' | grep -v '#' | while read line; do
            kv `echo $line`
          done
          ;;
       *)
          ;;
    esac
}
