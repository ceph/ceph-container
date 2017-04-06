#!/bin/bash
set -e

function kv {
  # Note the 'cas' command puts a value in the KV store if it is empty
  KEY="$1"
  shift
  VALUE="$*"
  log "Adding key ${KEY} with value ${VALUE} to KV store."
  etcdctl $ETCDCTL_OPTS ${KV_TLS} set ${CLUSTER_PATH}"${KEY}" "${VALUE}" || log "Value is already set"
}

function populate_kv {
  if [[ -z $KV_TYPE ]]; then
    echo "Please specify a KV store, e.g: etcd."
    exit 1
  fi
  case "$KV_TYPE" in
    etcd)
      # if ceph.defaults found in /etc/ceph/ use that
      if [[ -e "/etc/ceph/ceph.defaults" ]]; then
        DEFAULTS_PATH="/etc/ceph/ceph.defaults"
      else
        # else use defaults
        DEFAULTS_PATH="/ceph.defaults"
      fi
      # read defaults file, grab line with key<space>value without comment #
      grep '^.* .*' "$DEFAULTS_PATH" | grep -v '#' | while read line; do
        kv `echo $line`
      done
      ;;
    *)
      echo "$KV_TYPE: KV store is not supported."
      exit 1
      ;;
  esac
}
