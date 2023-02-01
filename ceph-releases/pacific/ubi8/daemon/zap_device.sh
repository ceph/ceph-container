#!/bin/bash
set -e

# Get a list of child devices from a root device
function get_child_partitions {
# $1: raw parent device
  if [ ! -e  "${1}" ] && [ ! -b "${1}" ]; then
    log "Error, ${1} doesn't seem to be a valid device!"
    exit 1
  fi
  local parts
  parts=$(lsblk -no KNAME "${1}")
  for p in $parts; do
    kname=$(lsblk --nodeps -no KNAME /dev/"${p}")
    pkname=$(lsblk --nodeps -no PKNAME /dev/"${p}")
    if [ "${kname}" != "${pkname}" ] && [ -n "${pkname}" ]; then
      echo /dev/"${p}"
    fi
  done
}

function get_dmcrypt_uuid_part {
  # look for Ceph encrypted partitions
  # Get all dmcrypt for ${device}
  blkid -t TYPE="crypto_LUKS" "${1}"* -o value -s PARTUUID || true
}

function get_opened_dmcrypt {
  # Get actual opened dmcrypt for ${device}
  dmsetup ls --exec 'basename' --target crypt
}

function zap_dmcrypt_device {
  # $1: list of cryptoluks partitions (returned by get_dmcrypt_uuid_part)
  # $2: list of opened dm (returned by get_opened_dmcrypt)
  local dm_uuid
  for dm_uuid in $1; do
    for dm in $2; do
      if [ "${dm_uuid}" == "${dm}" ]; then
        cryptsetup luksClose /dev/mapper/"${dm_uuid}"
      fi
    done
    dm_path="/dev/disk/by-partuuid/${dm_uuid}"
    dmsetup wipe_table --force "${dm_uuid}" || log "Warning: dmsetup wipe_table non-zero return code"
    dmsetup remove --force --retry "${dm_uuid}" || log "Warning: dmsetup remove non-zero return code"
    # erase all keyslots (remove encryption key)
    payload_offset=$(cryptsetup luksDump "${dm_path}" | awk '/Payload offset:/ { print $3 }')
    phys_sector_size=$(blockdev --getpbsz "${dm_path}")
    # If the sector size isn't a number, let's default to 512
    if ! is_integer "${phys_sector_size}"; then
      phys_sector_size=512
    fi
    # remove LUKS header
    dd if=/dev/zero of="${dm_path}" bs="${phys_sector_size}" count="${payload_offset}" oflag=direct
  done
}

function get_all_ceph_devices {
  local all_devices
  # Let's iterate over all devices on the node.
  for device in $(blkid -o device); do
    local partlabel
    # get the partlabel for the current device.
    partlabel=$(blkid "${device}" -s PARTLABEL -o value)

    # some device might not have partlabel, it means ${partlabel} will be empty
    # in that case, simply jump to the next iteration.
    if [ -z "$partlabel" ]; then
      continue
    fi

    # if the partlabel doesn't start with 'ceph', it means this is not a ceph used partition.
    # in that case, simply jump to the next iteration.
    if [[ ! "$partlabel" =~ ^ceph.* ]]; then
      continue
    fi

    # if we reach this point, it means we found a ceph partition,
    # let's find its raw parent device and add it to the list.
    local parent_dev
    parent_dev=$(lsblk --nodeps -pno PKNAME "${device}")
    if [ -n "${parent_dev}" ]; then
      all_devices+=("${parent_dev}")
    fi
  done

  # Finally, print all the devices with only 1 occurence for each device (uniq)
  echo "${all_devices[@]}" | tr ' ' '\n' | sort -u
}

function zap_device {
  local phys_sector_size
  local dm_path
  local ceph_dm
  local payload_offset

  if [[ -z ${OSD_DEVICE} ]]; then
    log "Please provide device(s) to zap!"
    log "ie: '-e OSD_DEVICE=/dev/sdb' or '-e OSD_DEVICE=/dev/sdb,/dev/sdc'"
    exit 1
  fi

  if [[ "${OSD_DEVICE}" == "all_ceph_disks" ]]; then
    OSD_DEVICE=$(get_all_ceph_devices)
  fi

  for device in $(comma_to_space "${OSD_DEVICE}"); do
    if [ ! -b "${device}" ]; then
      log "Provided device ${device} is not a block special file."
      exit 1
    fi

    # if the disk passed is a raw device AND the boot system disk
    [[ $(lsblk --nodeps -no LABEL "${device}") == "boot" ]] && log "Looks like ${device} has a boot partition," &&
      log "if you want to delete specific partitions point to the partition instead of the raw device" &&
      log "Do not use your system disk!" &&
      exit 1
    if is_dmcrypt "${device}"; then
    # If dmcrypt partitions detected, loop over all uuid found and check whether they are still opened.
      ceph_dm=$(get_dmcrypt_uuid_part "${device}")
      opened_dm=$(get_opened_dmcrypt "${device}")
      zap_dmcrypt_device "$ceph_dm" "$opened_dm"
    fi
    pkname=$(lsblk --nodeps -no PKNAME "${device}")
    if [ -z "$pkname" ]; then
    # are we zapping an entire block device or just a partition?
    # if pkname is empty then yes
      partitions=$(get_child_partitions "${device}")
      log "Zapping the entire device ${device}"
      for part in $partitions; do
        wipefs --all "${part}"
        dd if=/dev/zero of="${part}" bs=1 count=4096
      done
      sgdisk --zap-all --clear --mbrtogpt -g -- "${device}"
      dd if=/dev/zero of="${device}" bs=1M count=10
      parted -s "${device}" mklabel gpt
      log "Executing partprobe on ${device}"
      partprobe "${device}"
      udevadm settle
    else
      # seems to be a partition
      log "Zapping partition $device"
      wipefs --all "${device}"
      dd if=/dev/zero of="${device}" bs=1M count=10
      local partition_nb
      partition_nb=$(echo "$device" | grep -oE '[0-9]{1,2}$')
      sgdisk --delete "$partition_nb" /dev/"$pkname"
    fi
  done
}
