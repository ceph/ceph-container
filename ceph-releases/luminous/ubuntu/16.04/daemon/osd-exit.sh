#!/bin/bash

set -e

ceph_mnt=$(findmnt --nofsroot --noheadings --output SOURCE --submounts --target /var/lib/ceph/osd/ | tail -n +2)
for mnt in $ceph_mnt; do
  log "Unmounting $mnt"
  umount "$mnt"
done
