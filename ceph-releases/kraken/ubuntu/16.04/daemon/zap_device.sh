#!/bin/bash
set -e

function zap_device {
  if [[ -z ${OSD_DEVICE} ]]; then
    log "Please provide device(s) to zap!"
    log "ie: '-e OSD_DEVICE=/dev/sdb' or '-e OSD_DEVICE=/dev/sdb,/dev/sdc'"
    exit 1
  fi

  # testing all the devices first so we just don't do anything if one device is wrong
  for device in $(echo ${OSD_DEVICE} | tr "," " "); do
    if ! file -s $device &> /dev/null; then
      log "Provided device $device does not exist."
      exit 1
    fi
    # if the disk passed is a raw device AND the boot system disk
    if echo $device | egrep -sq '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}$' && parted -s $(echo $device | egrep -o '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}') print | grep -sq boot; then
      log "Looks like $device has a boot partition,"
      log "if you want to delete specific partitions point to the partition instead of the raw device"
      log "Do not use your system disk!"
      exit 1
    fi
  done

  # look for Ceph encrypted partitions
  ceph_dm=$(blkid -t TYPE="crypto_LUKS" ${OSD_DEVICE}* -o value -s PARTUUID || true)
  if [[ ! -z $ceph_dm ]]; then
    for dm_uuid in $ceph_dm; do
      dmsetup --verbose --force wipe_table $dm_uuid || true
      dmsetup --verbose --force remove $dm_uuid || true
    done
  fi

  for device in $(echo ${OSD_DEVICE} | tr "," " "); do
    raw_device=$(echo $device | egrep -o '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}')
    if echo $device | egrep -sq '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}$'; then
      log "Zapping the entire device $device"
      sgdisk --zap-all --clear --mbrtogpt -g -- $device
    else
      # get the desired partition number(s)
      partition_nb=$(echo $device | egrep -o '[0-9]{1,2}$')
      log "Zapping partition $device"
      sgdisk --delete $partition_nb $raw_device
    fi
    log "Executing partprobe on $raw_device"
    partprobe $raw_device
    udevadm settle
  done
}
