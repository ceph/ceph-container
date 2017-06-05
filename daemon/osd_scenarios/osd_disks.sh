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

  # Create the directory and an empty Procfile
  mkdir -p /etc/forego/${CLUSTER}
  echo "" > /etc/forego/${CLUSTER}/Procfile

  # check if anything is there, if not create an osd with directory
  if [[ -z "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Mount existing and prepared OSD disks for ceph-cluster ${CLUSTER}"
    for OSD_ID in $(ls /var/lib/ceph/osd | sed 's/.*-//'); do
      OSD_PATH=$(get_osd_path $OSD_ID)
      OSD_KEYRING="$OSD_PATH/keyring"
      OSD_DEV=$(get_osd_dev ${OSD_ID})
      if [[ -z ${OSD_DEV} ]]; then
        log "No device mapping for ${CLUSTER}-${OSD_ID} for ceph-cluster ${CLUSTER}"
        exit 1
      fi
      mount ${MOUNT_OPTS} $(dev_part ${OSD_DEV} 1) $OSD_PATH
      xOSD_ID=$(cat $OSD_PATH/whoami)
      if [[ "${OSD_ID}" != "${xOSD_ID}" ]]; then
        log "Device ${OSD_DEV} is corrupt for $OSD_PATH"
        exit 1
      fi
      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CLI_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/${CLUSTER}/Procfile
    done
    exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
  fi

  #
  # As per the exec in the first statement, we only reach here if there is some OSDs
  #
  for OSD_DISK in ${OSD_DISKS}; do
    OSD_DEV="/dev/$(echo ${OSD_DISK}|sed 's/\(.*\):\(.*\)/\2/')"

    if [[ "$(parted --script ${OSD_DEV} print | egrep '^ 1.*ceph data')" ]]; then
      if [[ ${OSD_FORCE_ZAP} -eq 1 ]]; then
        ceph-disk -v zap ${OSD_DEV}
      else
        log "ERROR- It looks like the device ($OSD_DEV) is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
        exit 1
      fi
    fi

    ceph-disk -v prepare ${CLI_OPTS} ${OSD_DEV} ${OSD_JOURNAL}

    # prepare the OSDs configuration and start them later
    start_osd forego
  done

  log "SUCCESS"
  # Actually, starting them as per forego configuration
  start_forego
}
