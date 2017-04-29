#!/bin/bash
set -e

function osd_activate_journal {
  if [[ -z "${OSD_JOURNAL}" ]];then
    log "ERROR- You must provide a device to build your OSD journal ie: /dev/sdb2"
    exit 1
  fi

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  # wait till partition exists
  wait_for "${OSD_JOURNAL}"

  chown --verbose ceph. "${OSD_JOURNAL}"
  ceph-disk -v --setuser ceph --setgroup disk activate-journal "${OSD_JOURNAL}"

  start_osd
}
