#!/bin/bash
set -e

function osd_activate_journal {
  if [[ -z "${OSD_JOURNAL}" ]];then
    log "ERROR- You must provide a device to build your OSD journal ie: /dev/sdb2"
    exit 1
  fi

  # wait till partition exists
  timeout 10  bash -c "while [ ! -e ${OSD_JOURNAL} ]; do sleep 1; done"

  chown ceph. ${OSD_JOURNAL}
  ceph-disk -v --setuser ceph --setgroup disk activate-journal ${OSD_JOURNAL}

  start_osd
}
