#!/bin/bash
set -e

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd
  # resolve /dev/disk/by-* names
  ACTUAL_OSD_DEVICE=$(readlink -f ${OSD_DEVICE})
  # wait till partition exists then activate it
  if [[ ! -z "${OSD_JOURNAL}" ]]; then
    timeout 10 bash -c "while [ ! -e ${OSD_DEVICE} ]; do sleep 1; done"
    chown ceph. ${OSD_JOURNAL}
    if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      ceph-disk -v --setuser ceph --setgroup disk activate --dmcrypt --no-start-daemon $(dev_part ${OSD_DEVICE} 1)
    else
      ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon $(dev_part ${OSD_DEVICE} 1)
    fi
    OSD_ID=$(grep "$(dev_part ${ACTUAL_OSD_DEVICE} 1)" /proc/mounts | awk '{print $2}' | grep -oh '[0-9]*')
  else
    timeout 10 bash -c "while [ ! -e $(dev_part ${OSD_DEVICE} 1) ]; do sleep 1; done"
    chown ceph. $(dev_part ${OSD_DEVICE} 2)
    if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      ceph-disk -v --setuser ceph --setgroup disk activate --dmcrypt --no-start-daemon $(dev_part ${OSD_DEVICE} 1)
    else
      ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon $(dev_part ${OSD_DEVICE} 1)
    fi
    OSD_ID=$(grep "$(dev_part ${ACTUAL_OSD_DEVICE} 1)" /proc/mounts | awk '{print $2}' | grep -oh '[0-9]*')
  fi
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  log "SUCCESS"
  exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk
}
