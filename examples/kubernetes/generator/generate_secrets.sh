#!/bin/bash

gen-fsid() {
  echo "$(uuidgen)"
}

gen-ceph-conf-raw() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  echo "$conf"
}

gen-ceph-conf() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  secret=$(echo "${conf}" | base64 | tr -d '\r\n')
  secret_output=$(sigil -f templates/kubernetes/secret.tmpl "name=ceph-conf" "key=ceph.conf" "val=${secret}")
  echo "${secret_output}"
}

gen-admin-keyring() {
  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/admin.keyring.tmpl "key=${key}")
  secret=$(echo "${keyring}" | base64 | tr -d '\r\n')
  secret_output=$(sigil -f templates/kubernetes/ceph-admin-secret.tmpl "key=${secret}")
  echo "${secret_output}"
}

gen-mon-keyring() {
  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/mon.keyring.tmpl "key=${key}")
  secret=$(echo "${keyring}" | base64 | tr -d '\r\n')
  secret_output=$(sigil -f templates/kubernetes/ceph-mon-secret.tmpl "key=${secret}")
  echo "${secret_output}"
}

gen-combined-conf() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  ceph_conf_val=$(echo "${conf}" | base64 | tr -d '\r\n')

  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/admin.keyring.tmpl "key=${key}")
  ceph_admin_keyring_val=$(echo "${keyring}" | base64 | tr -d '\r\n')

  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/mon.keyring.tmpl "key=${key}")
  ceph_mon_keyring_val=$(echo "${keyring}" | base64 | tr -d '\r\n')

  secret_output=$(sigil -f templates/kubernetes/ceph-conf-combined.tmpl "name=ceph-conf-combined" "ceph_conf_val=${ceph_conf_val}" "ceph_admin_keyring_val=${ceph_admin_keyring_val}" "ceph_mon_keyring_val=${ceph_mon_keyring_val}")
  echo "${secret_output}"
}

gen-bootstrap-keyring() {
  service="${1:-osd}"
  KEY=$(python ceph-key.py)
  bootstrap=$(sigil -f templates/ceph/bootstrap.keyring.tmpl "key=${KEY}" "service=${service}")
  secret=$(echo "${bootstrap}" | base64 | tr -d '\r\n')
  secret_output=$(sigil -f templates/kubernetes/ceph-bootstrap-secret.tmpl "key=${secret}" "service=${service}")
  echo "${secret_output}"
}

main() {
  set -eo pipefail
  case "$1" in
  fsid)            shift; gen-fsid $@;;
  ceph-conf-raw)            shift; gen-ceph-conf-raw $@;;
  ceph-conf)            shift; gen-ceph-conf $@;;
  admin-keyring)            shift; gen-admin-keyring $@;;
  mon-keyring)            shift; gen-mon-keyring $@;;
  bootstrap-keyring)            shift; gen-bootstrap-keyring $@;;
  combined-conf)               shift; gen-combined-conf $@;;
  esac
}

main "$@"