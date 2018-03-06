#!/bin/bash
set -e

function osd_disk_prepare {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  if [[ ! -e "${OSD_DEVICE}" ]]; then
    log "ERROR- The device pointed by OSD_DEVICE ($OSD_DEVICE) doesn't exist !"
    exit 1
  fi

  if [ ! -e "$OSD_BOOTSTRAP_KEYRING" ]; then
    log "ERROR- $OSD_BOOTSTRAP_KEYRING must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o $OSD_BOOTSTRAP_KEYRING'"
    exit 1
  fi

  ceph_health client.bootstrap-osd "$OSD_BOOTSTRAP_KEYRING"

  # check device status first
  if ! parted --script "${OSD_DEVICE}" print > /dev/null 2>&1; then
    if [[ ${OSD_FORCE_ZAP} -eq 1 ]]; then
      log "It looks like ${OSD_DEVICE} isn't consistent, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
      ceph-disk -v zap "${OSD_DEVICE}"
    else
      log "Regarding parted, device ${OSD_DEVICE} is inconsistent/broken/weird."
      log "It would be too dangerous to destroy it without any notification."
      log "Please set OSD_FORCE_ZAP to '1' if you really want to zap this disk."
      exit 1
    fi
  fi

  # then search for some ceph metadata on the disk
  if parted --script "${OSD_DEVICE}" print | grep -qE '^ 1.*ceph data'; then
    if [[ ${OSD_FORCE_ZAP} -eq 1 ]]; then
      log "It looks like ${OSD_DEVICE} is an OSD, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
      ceph-disk -v zap "${OSD_DEVICE}"
    else
      log "INFO- It looks like ${OSD_DEVICE} is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
      log "You can also use the zap_device scenario on the appropriate device to zap it"
      log "Moving on, trying to activate the OSD now."
      return
    fi
  fi

  IFS=" " read -r -a CEPH_DISK_CLI_OPTS <<< "${CLI_OPTS[*]}"
  if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    # We need to do a mapfile because ${OSD_LOCKBOX_UUID} needs to be quoted
    # so doing a regular CLI_OPTS+=("${OSD_LOCKBOX_UUID}") will make shellcheck unhappy.
    # Although the array can still be incremented by the others task using a regular += operator
    mapfile -t CEPH_DISK_CLI_OPTS_ARRAY <<< "${CEPH_DISK_CLI_OPTS[*]} --dmcrypt --lockbox-uuid ${OSD_LOCKBOX_UUID}"
    IFS=" " read -r -a CEPH_DISK_CLI_OPTS <<< "${CEPH_DISK_CLI_OPTS_ARRAY[*]}"
  fi
  if [[ "${OSD_FILESTORE}" -eq 1 ]]; then
    if [[ -n "${OSD_JOURNAL}" ]]; then
      ceph-disk -v prepare "${CEPH_DISK_CLI_OPTS[@]}" --journal-uuid "${OSD_JOURNAL_UUID}" "${OSD_DEVICE}" "${OSD_JOURNAL}"
    else
      ceph-disk -v prepare "${CEPH_DISK_CLI_OPTS[@]}" --journal-uuid "${OSD_JOURNAL_UUID}" "${OSD_DEVICE}"
    fi
  fi

  if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    # unmount lockbox partition when using dmcrypt
    umount_lockbox

    # close dmcrypt device
    # shellcheck disable=SC2034
    DATA_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
    # shellcheck disable=SC2034
    DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
    if [[ "${OSD_FILESTORE}" -eq 1 ]]; then
      get_dmcrypt_filestore_uuid
      close_encrypted_parts_filestore
    fi
  fi

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  apply_ceph_ownership_to_disks
}
