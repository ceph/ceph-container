#!/bin/bash

gen-fsid() {
  echo "$(uuidgen)"
}

gen-ceph-conf-raw() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  echo "${conf}"
}

gen-ceph-conf() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  echo "${conf}"
}

gen-admin-keyring() {
  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/admin.keyring.tmpl "key=${key}")
  echo "${keyring}"
}

gen-mon-keyring() {
  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/mon.keyring.tmpl "key=${key}")
  echo "${keyring}"
}

gen-combined-conf() {
  fsid=${1:?}
  shift
  conf=$(sigil -p -f templates/ceph/ceph.conf.tmpl "fsid=${fsid}" $@)
  echo "${conf}" > ceph.conf

  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/admin.keyring.tmpl "key=${key}")
  echo "${key}" > ceph-client-key
  echo "${keyring}" > ceph.client.admin.keyring

  key=$(python ceph-key.py)
  keyring=$(sigil -f templates/ceph/mon.keyring.tmpl "key=${key}")
  echo "${keyring}" > ceph.mon.keyring
}

gen-bootstrap-keyring() {
  service="${1:-osd}"
  key=$(python ceph-key.py)
  bootstrap=$(sigil -f templates/ceph/bootstrap.keyring.tmpl "key=${key}" "service=${service}")
  echo "${bootstrap}"
}

gen-all-bootstrap-keyrings() {
  gen-bootstrap-keyring osd > ceph.osd.keyring
  gen-bootstrap-keyring mds > ceph.mds.keyring
  gen-bootstrap-keyring rgw > ceph.rgw.keyring
}

gen-all() {
  gen-combined-conf $@
  gen-all-bootstrap-keyrings
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
  all)                         shift; gen-all $@;;
  esac
}

main "$@"
