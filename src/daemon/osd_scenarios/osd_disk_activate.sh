#!/bin/bash
set -e

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]] || [[ ! -b "${OSD_DEVICE}" ]]; then
    log "ERROR: you either provided a non-existing device or no device at all."
    log "You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  if ! parted --script "${OSD_DEVICE}" print | grep -qE '^ 1.*ceph data'; then
    log "ERROR: ${OSD_DEVICE} doesn't have a ceph metadata partition"
    exit 1
  fi

  if ! test -d /etc/ceph/osd || ! grep -q ${OSD_DEVICE}1 /etc/ceph/osd/*.json; then
    log "INFO: Scanning ${OSD_DEVICE}"
    ceph-volume simple scan ${OSD_DEVICE}1
  fi

  CEPH_VOLUME_SCAN_FILE=$(grep -l ${OSD_DEVICE}1 /etc/ceph/osd/*.json)

  # Find the OSD ID
  OSD_ID="$(cat ${CEPH_VOLUME_SCAN_FILE} | $PYTHON -c "import sys, json; print(json.load(sys.stdin)[\"whoami\"])")"

  # Activate the OSD
  # The command can fail so if it does, let's output the ceph-volume logs
  if ! ceph-volume simple activate --file ${CEPH_VOLUME_SCAN_FILE} --no-systemd; then
    cat /var/log/ceph
    exit 1
  fi

  log "SUCCESS"
  # This ensures all resources have been unmounted after the OSD has exited
  # We define `sigterm_cleanup_post` here because:
  # - we want to 'protect' the following `exec` in particular.
  # - having the cleaning code just next to the concerned function in the same file is nice.
  function sigterm_cleanup_post {
    local ceph_mnt
    ceph_mnt=$(findmnt --nofsroot --noheadings --output SOURCE --submounts --target /var/lib/ceph/osd/ | grep '^/')
    for mnt in $ceph_mnt; do
      log "osd_disk_activate: Unmounting $mnt"
      umount "$mnt" || (log "osd_disk_activate: Failed to umount $mnt"; lsof "$mnt")
    done
  }
  exec /usr/bin/ceph-osd "${DAEMON_OPTS[@]}" -i "${OSD_ID}"
}
