#!/bin/bash
set -e

function osd_disk_prepare {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi
  if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
    log "ERROR- /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring'"
    exit 1
  fi
  timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1
  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd

  # TODO:
  # -  add device format check (make sure only one device is passed
  # check device status first
  if ! parted --script ${OSD_DEVICE} print > /dev/null 2>&1; then
    ceph-disk -v zap ${OSD_DEVICE}
  fi
  if [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -ne "1" ]]; then
    log "INFO- It looks like ${OSD_DEVICE} is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
    log "You can also use the zap_device scenario on the appropriate device to zap it"
    log "Moving on, trying to activate the OSD now."
    return
  elif [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -eq "1" ]]; then
    log "It looks like ${OSD_DEVICE} is an OSD, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
    ceph-disk -v zap ${OSD_DEVICE}
  fi
  if [[ ! -z "${OSD_JOURNAL}" ]]; then
    if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
      ceph-disk -v prepare ${CEPH_OPTS} --bluestore ${OSD_DEVICE} ${OSD_JOURNAL}
    elif [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      get_admin_key
      check_admin_key
      # the admin key must be present on the node
      # in order to store the encrypted key in the monitor's k/v store
      ceph-disk -v prepare ${CEPH_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} --lockbox-uuid ${OSD_LOCKBOX_UUID} --dmcrypt ${OSD_DEVICE} ${OSD_JOURNAL}
      echo "Unmounting LOCKBOX directory"
      # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
      # Ceph bug tracker: http://tracker.ceph.com/issues/18944
      umount /var/lib/ceph/osd-lockbox/$(blkid -o value -s PARTUUID ${OSD_DEVICE}1) || true
    else
      ceph-disk -v prepare ${CEPH_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} ${OSD_DEVICE} ${OSD_JOURNAL}
    fi
    chown ceph. ${OSD_JOURNAL}
  else
    if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
      ceph-disk -v prepare ${CEPH_OPTS} --bluestore ${OSD_DEVICE}
    elif [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      get_admin_key
      check_admin_key
      # the admin key must be present on the node
      # in order to store the encrypted key in the monitor's k/v store
      ceph-disk -v prepare ${CEPH_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} --lockbox-uuid ${OSD_LOCKBOX_UUID} --dmcrypt ${OSD_DEVICE}
      echo "Unmounting LOCKBOX directory"
      # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
      # Ceph bug tracker: http://tracker.ceph.com/issues/18944
      umount /var/lib/ceph/osd-lockbox/$(blkid -o value -s PARTUUID ${OSD_DEVICE}1) || true
    else
      ceph-disk -v prepare ${CEPH_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} ${OSD_DEVICE}
    fi
    chown ceph. $(dev_part ${OSD_DEVICE} 2)
  fi
}
