#!/bin/bash
# shellcheck disable=SC2034
set -e
source disk_list.sh

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]] || [[ ! -b "${OSD_DEVICE}" ]]; then
    log "ERROR: you either provided a non-existing device or no device at all."
    log "You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  CEPH_DISK_OPTIONS=()

  if [[ ${OSD_FILESTORE} -eq 1 ]] && [[ ${OSD_DMCRYPT} -eq 0 ]]; then
    if [[ -n "${OSD_JOURNAL}" ]]; then
      CLI+=("${OSD_JOURNAL}")
    else
      CLI+=("${OSD_DEVICE}")
    fi
    export DISK_LIST_SEARCH=journal
    start_disk_list
    JOURNAL_PART=$(start_disk_list)
    unset DISK_LIST_SEARCH
    JOURNAL_UUID=$(get_part_uuid "${JOURNAL_PART}")
  fi

  # creates /dev/mapper/<uuid> for dmcrypt
  # usually after a reboot they don't go created
  udevadm trigger

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
  MOUNTED_PART=${DATA_PART}

  if [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_FILESTORE} -eq 1 ]]; then
    get_dmcrypt_filestore_uuid
    mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
    CEPH_DISK_OPTIONS+=('--dmcrypt')
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"
    open_encrypted_parts_filestore
  elif [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    get_dmcrypt_bluestore_uuid
    mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
    CEPH_DISK_OPTIONS+=('--dmcrypt')
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"
    open_encrypted_parts_bluestore
  fi

  if [[ -z "${CEPH_DISK_OPTIONS[*]}" ]]; then
    ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon "${DATA_PART}"
  else
    ceph-disk -v --setuser ceph --setgroup disk activate "${CEPH_DISK_OPTIONS[@]}" --no-start-daemon "${DATA_PART}"
  fi

  actual_part=$(readlink -f "${MOUNTED_PART}")
  OSD_ID=$(grep "${actual_part}" /proc/mounts | awk '{print $2}' | sed -r 's/^.*-([0-9]+)$/\1/')

  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    # Get the device used for block db and wal otherwise apply_ceph_ownership_to_disks will fail
    OSD_BLUESTORE_BLOCK_DB_TMP=$(resolve_symlink "${OSD_PATH}block.db")
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_DB=${OSD_BLUESTORE_BLOCK_DB_TMP%?}
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_WAL_TMP=$(resolve_symlink "${OSD_PATH}block.wal")
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_WAL=${OSD_BLUESTORE_BLOCK_WAL_TMP%?}
  fi
  apply_ceph_ownership_to_disks

  log "SUCCESS"
  # This ensures all resources have been unmounted after the OSD has exited
  # We define `sigterm_cleanup_post` here because:
  # - we want to 'protect' the following `exec` in particular.
  # - having the cleaning code just next to the concerned function in the same file is nice.
  function sigterm_cleanup_post {
    local ceph_mnt
    ceph_mnt=$(findmnt --nofsroot --noheadings --output SOURCE --submounts --target /var/lib/ceph/osd/ | tail -n +2)
    for mnt in $ceph_mnt; do
      log "osd_disk_activate: Unmounting $mnt"
      umount "$mnt" || (log "osd_disk_activate: Failed to umount $mnt"; lsof $mnt)
    done
  }
  exec /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i "${OSD_ID}" --setuser ceph --setgroup disk
}
