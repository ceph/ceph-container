#!/bin/bash
set -e

: "${OSD_DISKS:=none}"
: "${OSD_JOURNAL:=none}"

function osd_disks {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi
  if [[ ${OSD_DISKS} == "none" ]]; then
    log "ERROR- could not find the osd devices, did you configure OSD disks?"
    log "ERROR- use -e OSD_DISKS=\"0:sdd 1:sde 2:sdf\""
    exit 1
  fi

  # Create the directory and an empty Procfile
  mkdir -p /etc/forego/"${CLUSTER}"
  echo "" > /etc/forego/"${CLUSTER}"/Procfile

  # check if anything is there, if not create an osd with directory
  if [[ -z "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Mount existing and prepared OSD disks for ceph-cluster ${CLUSTER}"
    for OSD_ID in $(find /var/lib/ceph/osd -maxdepth 1 -mindepth 1 -name "${CLUSTER}*" | sed 's/.*-//'); do
      OSD_PATH=$(get_osd_path "$OSD_ID")
      OSD_DEVICE=$(get_osd_dev "${OSD_ID}")
      if [[ -z ${OSD_DEVICE} ]]; then
        log "No device mapping for ${CLUSTER}-${OSD_ID} for ceph-cluster ${CLUSTER}"
        exit 1
      fi
      mount "${MOUNT_OPTS[@]}" "$(dev_part "${OSD_DEVICE}" 1)" "$OSD_PATH"
      xOSD_ID=$(cat "$OSD_PATH"/whoami)
      if [[ "${OSD_ID}" != "${xOSD_ID}" ]]; then
        log "Device ${OSD_DEVICE} is corrupt for $OSD_PATH"
        exit 1
      fi
      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/"${CLUSTER}"/Procfile
    done
  else
    #
    # As per the exec in the first statement, we only reach here if there is some OSDs
    #
    for OSD_DISK in ${OSD_DISKS}; do
      OSD_DEV="/dev/$(echo "${OSD_DISK}"|sed 's/\(.*\):\(.*\)/\2/')"
      OSD_DEVICE=$(readlink -f "${OSD_DEV}")
      OSD_ID="$(echo "${OSD_DISK}"|sed 's/\(.*\):\(.*\)/\1/')"

      if parted --script "${OSD_DEVICE}" print | grep -qE '^ 1.*ceph data'; then
        log "ERROR: It looks like the device ($OSD_DEVICE) is an OSD"
        log "You can use the zap_device scenario on the appropriate device to zap it."
        exit 1
      fi
      if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
        CEPH_DISK_CLI_OPTS+=(--bluestore)
        ceph-disk -v prepare "${CEPH_DISK_CLI_OPTS[@]}" \
        --block.wal "${OSD_DEVICE}" \
        --block.wal-uuid "$(uuidgen)" \
        --block.db "${OSD_DEVICE}" \
        --block.db-uuid "$(uuidgen)" \
        --block-uuid "$(uuidgen)" \
        "${OSD_DEVICE}"
      elif [[ "${OSD_FILESTORE}" -eq 1 ]]; then
        CEPH_DISK_CLI_OPTS+=(--filestore)
        if [[ ${OSD_JOURNAL} == "none" ]]; then
          ceph-disk -v prepare "${CEPH_DISK_CLI_OPTS[@]}" --journal-uuid "$(uuidgen)" "${OSD_DEVICE}"
        else
          ceph-disk -v prepare "${CEPH_DISK_CLI_OPTS[@]}" --journal-uuid "$(uuidgen)" "${OSD_DEVICE}" "${OSD_JOURNAL}"
        fi
      fi
      # watch the udev event queue, and exit if all current events are handled
      ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon $(dev_part ${OSD_DEVICE} 1)
      if [[ "${OSD_FILESTORE}" -eq 1 ]]; then
        OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
        ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}
      fi

      # prepare the OSDs configuration and start them later
      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/"${CLUSTER}"/Procfile
    done

  fi

log "SUCCESS"
  # Actually, starting them as per forego configuration
  exec /usr/local/bin/forego start -f /etc/forego/"${CLUSTER}"/Procfile
}
