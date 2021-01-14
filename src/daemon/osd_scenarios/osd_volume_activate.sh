#!/bin/bash
set -e

function osd_volume_simple {
  # Find the devices used by ceph-disk
  DEVICES=$(ceph-volume inventory --format json | $PYTHON -c 'import sys, json; print(" ".join([d.get("path") for d in json.load(sys.stdin) if "Used by ceph-disk" in d.get("rejected_reasons")]))')

  # Scan devices with ceph data partition
  for device in ${DEVICES}; do
    if parted --script "${device}" print | grep -qE '^ 1.*ceph data'; then
      OSD_DEVICE=${device}
      DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
      MOUNTED_PART=${DATA_PART}
      if [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_FILESTORE} -eq 1 ]]; then
        get_dmcrypt_filestore_uuid || true
        mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
        MOUNTED_PART="/dev/mapper/${DATA_UUID}"
        open_encrypted_parts_filestore
      elif [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_BLUESTORE} -eq 1 ]]; then
        get_dmcrypt_bluestore_uuid  || true
        mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
        # shellcheck disable=SC2034
        MOUNTED_PART="/dev/mapper/${DATA_UUID}"
        open_encrypted_parts_bluestore
      fi
      ceph-volume simple scan "${DATA_PART}" --force || true
      if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
        umount_lockbox
      fi
    fi
  done

  # Find the OSD json file associated to the ID
  #shellcheck disable=SC2153
  OSD_JSON=$(grep -l "whoami\": ${OSD_ID}$" /etc/ceph/osd/*.json)
  if [ -z "${OSD_JSON}" ]; then
    log "OSD id ${OSD_ID} does not exist"
    exit 1
  fi

  # Activate the OSD
  # The command can fail so if it does, let's output the ceph-volume logs
  if ! ceph-volume simple activate --file "${OSD_JSON}" --no-systemd; then
    cat /var/log/ceph
    exit 1
  fi
}

function get_dmcrypt_uuids {
  dmsetup ls --target=crypt | cut -d$'\t' -f 1
}

function osd_volume_lvm {
  # Find the OSD FSID from the OSD ID
  OSD_FSID="$(echo "$CEPH_VOLUME_LIST_JSON" | $PYTHON -c "import sys, json; print(json.load(sys.stdin)['$OSD_ID'][0]['tags']['ceph.osd_fsid'])")"

  # Find the OSD type
  OSD_TYPE="$(echo "$CEPH_VOLUME_LIST_JSON" | $PYTHON -c "import sys, json; print(json.load(sys.stdin)['$OSD_ID'][0]['type'])")"

  # Discover the objectstore
  if [[ "data journal" =~ $OSD_TYPE ]]; then
    OSD_OBJECTSTORE=(--filestore)
  elif [[ "block wal db" =~ $OSD_TYPE ]]; then
    OSD_OBJECTSTORE=(--bluestore)
  else
    log "Unable to discover osd objectstore for OSD type: $OSD_TYPE"
    exit 1
  fi

  # Activate the OSD
  # The command can fail so if it does, let's output the ceph-volume logs
  if ! ceph-volume lvm activate --no-systemd "${OSD_OBJECTSTORE[@]}" "${OSD_ID}" "${OSD_FSID}"; then
    cat /var/log/ceph
    exit 1
  fi
}

function osd_volume_activate {
  : "${OSD_ID:?Give me an OSD ID to activate, eg: -e OSD_ID=0}"

  ulimit -Sn 1024
  ulimit -Hn 4096

  CEPH_VOLUME_LIST_JSON="$(ceph-volume lvm list --format json)"

  #shellcheck disable=SC2153
  if echo "$CEPH_VOLUME_LIST_JSON" | $PYTHON -c "import sys, json; print(json.load(sys.stdin)['$OSD_ID'])" &> /dev/null; then
    OSD_VOLUME_TYPE=lvm
  else
    OSD_VOLUME_TYPE=simple
  fi

  if [[ "$OSD_VOLUME_TYPE" == "lvm" ]]; then
    osd_volume_lvm
  else
    osd_volume_simple
  fi

  log "SUCCESS"
  # This ensures all resources have been unmounted after the OSD has exited
  # We define `sigterm_cleanup_post` here because:
  # - we want to 'protect' the following `exec` in particular.
  # - having the cleaning code just next to the concerned function in the same file is nice.
  function sigterm_cleanup_post {
    local ceph_mnt
    ceph_mnt="/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}"
    log "osd_volume_activate: Unmounting $ceph_mnt"
    umount "$ceph_mnt" || (log "osd_volume_activate: Failed to umount $ceph_mnt"; lsof "$ceph_mnt")

    UUIDS=$(get_dmcrypt_uuids)

    for uuid in ${UUIDS}; do
      if [[ "$OSD_VOLUME_TYPE" == "simple" ]]; then
        DATA="${OSD_JSON}"
      else
        DATA=$(echo "$CEPH_VOLUME_LIST_JSON" | $PYTHON -c "import sys, json; print(json.load(sys.stdin)['$OSD_ID'])")
      fi
      if echo "${DATA}" | grep -qo "${uuid}"; then
        log "osd_volume_activate: Closing dmcrypt $uuid"
        cryptsetup close "${uuid}" || log "osd_volume_activate: Failed to close dmcrypt ${uuid}"
      fi
    done
  }
  # /usr/lib/systemd/system/ceph-osd@.service
  # LimitNOFILE=1048576
  # LimitNPROC=1048576
  ulimit -n 1048576 -u 1048576
  exec /usr/bin/ceph-osd "${DAEMON_OPTS[@]}" -i "${OSD_ID}"
}
