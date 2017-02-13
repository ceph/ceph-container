#!/bin/bash
set -e

function osd_disks {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi
  if [[  -z ${OSD_DISKS} ]]; then
    log "ERROR- could not find the osd devices, did you configure OSD disks?"
    log "ERROR- use -e OSD_DISKS=\"0:sdd 1:sde 2:sdf\""
    exit 1
  fi

  # make sure ceph owns the directory
  chown ceph. /var/lib/ceph/osd

  # Create the directory and an empty Procfile
  mkdir -p /etc/forego/${CLUSTER}
  echo "" > /etc/forego/${CLUSTER}/Procfile

  # check if anything is there, if not create an osd with directory
  if [[ -z "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Mount existing and prepared OSD disks for ceph-cluster ${CLUSTER}"
    for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }'); do
      OSD_DEV=$(get_osd_dev ${OSD_ID})
      if [[ -z ${OSD_DEV} ]]; then
        log "No device mapping for ${CLUSTER}-${OSD_ID} for ceph-cluster ${CLUSTER}"
        exit 1
      fi
      mount ${MOUNT_OPTS} $(dev_part ${OSD_DEV} 1) /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/
      xOSD_ID=$(cat /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/whoami)
      if [[ "${OSD_ID}" != "${xOSD_ID}" ]]; then
        log "Device ${OSD_DEV} is corrupt for /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}"
        exit 1
      fi
      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/${CLUSTER}/Procfile
    done
    exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
  else
    for i in ${OSD_DISKS}; do
      OSD_ID=$(echo ${i}|sed 's/\(.*\):\(.*\)/\1/')
      OSD_DEV="/dev/$(echo ${i}|sed 's/\(.*\):\(.*\)/\2/')"
      if [[ "$(parted --script ${OSD_DEV} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -ne "1" ]]; then
        log "ERROR- It looks like this device is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
        exit 1
      elif [[ "$(parted --script ${OSD_DEV} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -eq "1" ]]; then
        ceph-disk -v zap ${OSD_DEV}
      fi
      if [[ ! -z "${OSD_JOURNAL}" ]]; then
        ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEV} ${OSD_JOURNAL}
#        chown ceph. ${OSD_JOURNAL}
        ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEV} 1)
      else
        ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEV}
#        chown ceph. $(dev_part ${OSD_DEV} 2)
        ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEV} 1)
      fi
      OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
      OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

      # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID}
      # wait till docker stop or ceph-osd is killed
      OSD_PID=$(ps -ef |grep ceph-osd |grep osd.${OSD_ID} |awk '{print $2}')
      if [ -n "${OSD_PID}" ]; then
          log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
          while [ -e /proc/${OSD_PID} ]; do sleep 1;done
      fi
      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/${CLUSTER}/Procfile
    done
    log "SUCCESS"
    exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
  fi
}
