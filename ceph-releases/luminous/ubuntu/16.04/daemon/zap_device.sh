#!/bin/bash
set -e

function zap_device {
  local device_match_string='/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}'

  if [[ -z ${OSD_DEVICE} ]]; then
    log "Please provide device(s) to zap!"
    log "ie: '-e OSD_DEVICE=/dev/sdb' or '-e OSD_DEVICE=/dev/sdb,/dev/sdc'"
    exit 1
  fi

  # testing all the devices first so we just don't do anything if one device is wrong
  for device in $(comma_to_space "${OSD_DEVICE}"); do
    if [[ $(stat --format=%F "$device" 2> /dev/null) != "block special file" ]]; then
      log "Provided device $device does not exist."
      exit 1
    fi
    # if the disk passed is a raw device AND the boot system disk
    if echo "$device" | grep -sqE "${device_match_string}" && parted -s "$(echo "$device" | grep -Eo "${device_match_string}")" print | grep -sq boot; then
      log "Looks like $device has a boot partition,"
      log "if you want to delete specific partitions point to the partition instead of the raw device"
      log "Do not use your system disk!"
      exit 1
    fi
  done

  # look for Ceph encrypted partitions
  local ceph_dm
  ceph_dm=$(blkid -t TYPE="crypto_LUKS" "${OSD_DEVICE}"* -o value -s PARTUUID || true)
  if [[ -n $ceph_dm ]]; then
    for dm_uuid in $ceph_dm; do
      local dm_path="/dev/disk/by-partuuid/$dm_uuid"
      dmsetup --verbose --force wipe_table "$dm_uuid" || true
      dmsetup --verbose --force remove "$dm_uuid" || true

      # erase all keyslots (remove encryption key)
      cryptsetup --verbose --batch-mode erase "$dm_path"
      local payload_offset
      payload_offset=$(cryptsetup luksDump "$dm_path" | awk '/Payload offset:/ { print $3 }')
      local phys_sector_size
      phys_sector_size=$(blockdev --getpbsz "$dm_path")
      if ! is_integer "$phys_sector_size"; then
        # If the sector size isn't a number, let's default to 512
        phys_sector_size=512
      fi
      # remove LUKS header
      dd if=/dev/zero of="$dm_path" bs="$phys_sector_size" count="$payload_offset" oflag=direct
    done
  fi

  for device in $(comma_to_space "${OSD_DEVICE}"); do
    local raw_device
    raw_device=$(echo "$device" | grep -oE "${device_match_string}")
    if echo "$device" | grep -sqE "${device_match_string}"; then
      log "Zapping the entire device $device"
      sgdisk --zap-all --clear --mbrtogpt -g -- "$device"
    else
      # get the desired partition number(s)
      local partition_nb
      partition_nb=$(echo "$device" | grep -oE '[0-9]{1,2}$')
      log "Zapping partition $device"
      sgdisk --delete "$partition_nb" "$raw_device"
    fi
    log "Executing partprobe on $raw_device"
    partprobe "$raw_device"
    udevadm settle
  done
}
