#!/bin/bash
set -e

function osd_activate_journal {
  if [[ -z "${OSD_JOURNAL}" ]];then
    log "ERROR- You must provide a device to build your OSD journal ie: /dev/sdb2"
    exit 1
  fi

  # wait till partition exists
  timeout 10  bash -c "while [ ! -e ${OSD_JOURNAL} ]; do sleep 1; done"

  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd
  chown ceph. ${OSD_JOURNAL}
  ceph-disk -v --setuser ceph --setgroup disk activate-journal ${OSD_JOURNAL}

  OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID}
  # wait till docker stop or ceph-osd is killed
  OSD_PID=$(ps -ef |grep ceph-osd |grep osd.${OSD_ID} |awk '{print $2}')
  if [ -n "${OSD_PID}" ]; then
      log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
      while [ -e /proc/${OSD_PID} ]; do sleep 1;done
  else
      log "SUCCESS"
      exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk
  fi
}
