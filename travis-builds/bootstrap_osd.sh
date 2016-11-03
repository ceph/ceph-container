#!/usr/bin/env bash
set -xe


# FUNCTIONS
function do_aio_conf {
  # set pools replica size to 1 since we only have a single osd
  # also use a really low pg count
  echo "osd pool default size = 1" >> /etc/ceph/ceph.conf
  echo "osd pool default pg num = 8" >> /etc/ceph/ceph.conf
  echo "osd pool default pgp num = 8" >> /etc/ceph/ceph.conf
}

function bootstrap_osd {
  mkdir -p /var/lib/ceph/osd/ceph-0
  chown -R 64045:64045 /var/lib/ceph/osd/*
  docker exec ceph-mon ceph osd create
  docker exec ceph-mon ceph-osd -i 0 --mkfs
  docker exec ceph-mon ceph auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/ceph-0/keyring
  docker exec ceph-mon ceph osd crush add 0 1 root=default host=$(hostname -s)
  chown -R 64045:64045 /var/lib/ceph/osd/*
}


# MAIN
do_aio_conf
bootstrap_osd
