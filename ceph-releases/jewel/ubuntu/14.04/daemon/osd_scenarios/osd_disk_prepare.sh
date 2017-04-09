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

  if [ ! -e $OSD_BOOTSTRAP_KEYRING ]; then
    log "ERROR- $OSD_BOOTSTRAP_KEYRING must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o $OSD_BOOTSTRAP_KEYRING'"
    exit 1
  fi
  timeout 10 ceph ${CLI_OPTS} --name client.bootstrap-osd --keyring $OSD_BOOTSTRAP_KEYRING health || exit 1

  # check device status first
  if ! parted --script ${OSD_DEVICE} print > /dev/null 2>&1; then
    if [[ ${OSD_FORCE_ZAP} -eq 1 ]]; then
      log "It looks like ${OSD_DEVICE} isn't consistent, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
      ceph-disk -v zap ${OSD_DEVICE}
    else
      log "Regarding parted, device ${OSD_DEVICE} is inconsistent/broken/weird."
      log "It would be too dangerous to destroy it without any notification."
      log "Please set OSD_FORCE_ZAP to '1' if you really want to zap this disk."
      exit 1
    fi
  fi

  # then search for some ceph metadata on the disk
  if [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" ]]; then
    if [[ ${OSD_FORCE_ZAP} -eq 1 ]]; then
      log "It looks like ${OSD_DEVICE} is an OSD, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
      ceph-disk -v zap ${OSD_DEVICE}
    else
      log "INFO- It looks like ${OSD_DEVICE} is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
      log "You can also use the zap_device scenario on the appropriate device to zap it"
      log "Moving on, trying to activate the OSD now."
      return
    fi
  fi

  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    ceph-disk -v prepare ${CLI_OPTS} --bluestore ${OSD_DEVICE}
  elif [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    get_admin_key
    check_admin_key
    # the admin key must be present on the node
    # in order to store the encrypted key in the monitor's k/v store
    ceph-disk -v prepare ${CLI_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} --lockbox-uuid ${OSD_LOCKBOX_UUID} --dmcrypt ${OSD_DEVICE} ${OSD_JOURNAL}
    echo "Unmounting LOCKBOX directory"
    # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
    # Ceph bug tracker: http://tracker.ceph.com/issues/18944
    DATA_UUID=$(blkid -o value -s PARTUUID ${OSD_DEVICE}1)
    umount /var/lib/ceph/osd-lockbox/${DATA_UUID} || true
  else
    ceph-disk -v prepare ${CLI_OPTS} --journal-uuid ${OSD_JOURNAL_UUID} ${OSD_DEVICE} ${OSD_JOURNAL}
  fi

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  if [[ -n "${OSD_JOURNAL}" ]]; then
    wait_for_file ${OSD_JOURNAL}
    chown ceph. ${OSD_JOURNAL}
  else
    wait_for_file $(dev_part ${OSD_DEVICE} 2)
    chown ceph. $(dev_part ${OSD_DEVICE} 2)
  fi
}
