#!/bin/bash

# NOTE (leseb): I suspect that leaving the mountpoint opened
# after closing the namespace might cause some corruption.
# Especially in the context of encrypted OSDs.
#
# The idea here is to stop the osd AND unmount the partition(s)
# This is not easy since by design the container will exit
# if PID 1 stops.
#
# Ideally, during its shutdown process, the OSD will do that.

trap graceful_stop SIGTERM

function umount_ceph_mnt {
  local ceph_mnt
  ceph_mnt=$(findmnt --nofsroot --noheadings --output SOURCE --submounts --target /var/lib/ceph/osd/ | tail -n +2)
  for mnt in $ceph_mnt; do
    log "Unmounting $mnt"
    umount "$mnt"
  done
}

function handler {
  while true; do
    tail -f /dev/null & wait ${!}
  done
}

function graceful_stop {
  handler
  kill -SIGTERM 1
  wait 1
  umount_ceph_mnt
  exit 143; # 128 + 15 -- SIGTERM
}
