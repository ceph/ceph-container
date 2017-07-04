#!/bin/bash
set -e

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  CEPH_DISK_OPTIONS=()
  DATA_UUID=$(get_part_uuid "${OSD_DEVICE}"1)
  JOURNAL_PART=$(ceph-disk list "${OSD_DEVICE}" | awk '/ceph journal/ {print $1}') # This is privileged container so 'ceph-disk list' works
  JOURNAL_UUID=$(get_part_uuid "${JOURNAL_PART}")
  LOCKBOX_UUID=$(get_part_uuid "${OSD_DEVICE}"3 || true)

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
  MOUNTED_PART=${DATA_PART}

  if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    log "Mounting LOCKBOX directory"
    # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
    # Ceph bug tracker: http://tracker.ceph.com/issues/18945
    mkdir -p /var/lib/ceph/osd-lockbox/"${DATA_UUID}"
    mount /dev/disk/by-partuuid/"${LOCKBOX_UUID}" /var/lib/ceph/osd-lockbox/"${DATA_UUID}" || true
    local ceph_fsid
    local cluster_name
    cluster_name=$(basename "$(grep -R fsid /etc/ceph/ | grep -oE '^[^.]*')")
    ceph_fsid=$(ceph-conf --lookup fsid -c /etc/ceph/"$cluster_name".conf)
    echo "$ceph_fsid" > /var/lib/ceph/osd-lockbox/"${DATA_UUID}"/ceph_fsid
    chown --verbose ceph. /var/lib/ceph/osd-lockbox/"${DATA_UUID}"/ceph_fsid
    CEPH_DISK_OPTIONS+=('--dmcrypt')
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"

    # Open LUKS device(s) if necessary
    if [[ ! -e /dev/mapper/"${DATA_UUID}" ]]; then
      open_encrypted_part "${DATA_UUID}" "${DATA_PART}" "${DATA_UUID}"
    fi
    if [[ ! -e /dev/mapper/"${JOURNAL_UUID}" ]]; then
      open_encrypted_part "${JOURNAL_UUID}" "${JOURNAL_PART}" "${DATA_UUID}"
    fi
  fi

  if [[ -z "${CEPH_DISK_OPTIONS[*]}" ]]; then
    ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon "${DATA_PART}"
  else
    ceph-disk -v --setuser ceph --setgroup disk activate "${CEPH_DISK_OPTIONS[@]}" --no-start-daemon "${DATA_PART}"
  fi

  OSD_ID=$(grep "${MOUNTED_PART}" /proc/mounts | awk '{print $2}' | sed -r 's/^.*-([0-9]+)$/\1/')
  OSD_PATH=$(get_osd_path "$OSD_ID")
  OSD_KEYRING="$OSD_PATH/keyring"
  if [[ ${OSD_BLUESTORE} -eq 1 ]] && [ -e "${OSD_PATH}block" ]; then
    OSD_WEIGHT=$(awk "BEGIN { d= $(blockdev --getsize64 "${OSD_PATH}"block)/1099511627776 ; r = sprintf(\"%.2f\", d); print r }")
  else
    OSD_WEIGHT=$(df -P -k "$OSD_PATH" | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  fi

  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    # Get the device used for block db and wal otherwise apply_ceph_ownership_to_disks will fail
    OSD_BLUESTORE_BLOCK_DB_TMP=$(resolve_symlink "${OSD_PATH}block.db")
    OSD_BLUESTORE_BLOCK_DB=${OSD_BLUESTORE_BLOCK_DB_TMP%?}
    OSD_BLUESTORE_BLOCK_WAL_TMP=$(resolve_symlink "${OSD_PATH}block.wal")
    OSD_BLUESTORE_BLOCK_WAL=${OSD_BLUESTORE_BLOCK_WAL_TMP%?}
  fi
  apply_ceph_ownership_to_disks

  ceph "${CLI_OPTS[@]}" --name=osd."${OSD_ID}" --keyring="$OSD_KEYRING" osd crush create-or-move -- "${OSD_ID}" "${OSD_WEIGHT}" "${CRUSH_LOCATION}"

  log "SUCCESS"
  exec /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i "${OSD_ID}" --setuser ceph --setgroup disk
}
