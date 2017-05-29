#!/bin/bash

TEMPLATE_ENGINE=jinja

proc-template() {
  FILE=$1
  shift
  if [ "${TEMPLATE_ENGINE}" == "sigil" ]; then
    conf=$(sigil -p -f "${FILE}.tmpl" "$@")
    echo "${conf}"
  else
    TMPFILE=$(mktemp)
    for a in "$@"; do
      echo "${a/=/: !!str }" >> "${TMPFILE}"
    done
    conf=$(jinja2 --format=yaml "${FILE}.jinja" "${TMPFILE}")
    rm "${TMPFILE}"
    echo "${conf}"
  fi
}

gen-fsid() {
  uuidgen
}

gen-ceph-conf-raw() {
  fsid=${1:?}
  shift
  conf=$(proc-template templates/ceph/ceph.conf "fsid=${fsid}" "$@")
  echo "${conf}"
}

gen-ceph-conf() {
  fsid=${1:?}
  shift
  conf=$(proc-template templates/ceph/ceph.conf "fsid=${fsid}" "$@")
  echo "${conf}"
}

gen-admin-keyring() {
  key=$(python ceph-key.py)
  keyring=$(proc-template templates/ceph/admin.keyring "key=${key}")
  echo "${keyring}"
}

gen-mon-keyring() {
  key=$(python ceph-key.py)
  keyring=$(proc-template templates/ceph/mon.keyring "key=${key}")
  echo "${keyring}"
}

gen-combined-conf() {
  fsid=${1:?}
  shift
  conf=$(proc-template templates/ceph/ceph.conf "fsid=${fsid}" "$@")
  echo "${conf}" > ceph.conf

  key=$(python ceph-key.py)
  keyring=$(proc-template templates/ceph/admin.keyring "key=${key}")
  echo "${key}" > ceph-client-key
  echo "${keyring}" > ceph.client.admin.keyring

  key=$(python ceph-key.py)
  keyring=$(proc-template templates/ceph/mon.keyring "key=${key}")
  echo "${keyring}" > ceph.mon.keyring
}

gen-bootstrap-keyring() {
  service="${1:-osd}"
  key=$(python ceph-key.py)
  bootstrap=$(proc-template templates/ceph/bootstrap.keyring "key=${key}" "service=${service}")
  echo "${bootstrap}"
}

gen-all-bootstrap-keyrings() {
  gen-bootstrap-keyring osd > ceph.osd.keyring
  gen-bootstrap-keyring mds > ceph.mds.keyring
  gen-bootstrap-keyring rgw > ceph.rgw.keyring
}

gen-all() {
  gen-combined-conf "$@"
  gen-all-bootstrap-keyrings
}


main() {
  set -eo pipefail
  OP=$1
  shift
  case "$OP" in
  fsid)              gen-fsid "$@";;
  ceph-conf-raw)     gen-ceph-conf-raw "$@";;
  ceph-conf)         gen-ceph-conf "$@";;
  admin-keyring)     gen-admin-keyring "$@";;
  mon-keyring)       gen-mon-keyring "$@";;
  bootstrap-keyring) gen-bootstrap-keyring "$@";;
  combined-conf)     gen-combined-conf "$@";;
  all)               gen-all "$@";;
  esac
}

main "$@"

