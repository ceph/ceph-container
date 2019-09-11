#!/bin/bash
set -e


#############
# VARIABLES #
#############

DOCKER_ENV=""


#############
# FUNCTIONS #
#############

function mandatory_checks () {
  ami_privileged

  : "${OSD_DEVICE:=none}"
  if [[ ${OSD_DEVICE} == "none" ]]; then
    log "ERROR: you must submit OSD_DEVICE, e.g: -e OSD_DEVICE=/dev/sda"
    exit 1
  fi
}

function mount_ceph_data () {
  local mount_point="$1"
  if is_dmcrypt; then
    mount /dev/mapper/"${data_uuid}" "$mount_point"
  else
    data_part=$(dev_part "${OSD_DEVICE}" 1)
    mount /dev/disk/by-partuuid/"$(blkid -t PARTLABEL="ceph data" -s PARTUUID -o value ${data_part})" "$mount_point"
  fi
}

function umount_ceph_data () {
  local mount_point="$1"
  umount "$mount_point"
}

function get_docker_env () {
  mkdir -p /var/lib/ceph/tmp/
  local mount_point="$(mktemp --directory --tmpdir=/var/lib/ceph/tmp/)"
  mount_ceph_data "$mount_point"
  cd "$mount_point" || return
  if [[ -n ${1} ]]; then
    if [[ "${1}" == "whoami" ]]; then
      if is_dmcrypt; then
        cd /var/lib/ceph/osd-lockbox/"$data_uuid" || return
      fi
    fi
    if [[ -L ${1} ]]; then
      resolve_symlink "${1}"
    elif [[ -f ${1} ]]; then
      cat "${1}"
    fi
  else
    osd_type=$(<type)
    if [[ "$osd_type" == "filestore" ]]; then
      if [[ -L journal_dmcrypt ]]; then
        journal_part=$(resolve_symlink journal_dmcrypt)
        DOCKER_ENV="$DOCKER_ENV -e OSD_JOURNAL=$journal_part"
      elif [[ -L journal ]]; then
        journal_part=$(resolve_symlink journal)
        DOCKER_ENV="$DOCKER_ENV -e OSD_JOURNAL=$journal_part"
      fi
    # NOTE(leseb):
    # For bluestore we return the full device, not the partition
    # because apply_ceph_ownership_to_disks will determine the partitions
    # We could probably make this easier...
    elif [[ "$osd_type" == "bluestore" ]]; then
      if [[ -L block.db_dmcrypt ]]; then
        block_db_part=$(resolve_symlink block.db_dmcrypt)
        DOCKER_ENV="$DOCKER_ENV -e OSD_BLUESTORE_BLOCK_DB=${block_db_part%?}"
      elif [[ -L block.db ]]; then
        block_db_part=$(resolve_symlink block.db)
        DOCKER_ENV="$DOCKER_ENV -e OSD_BLUESTORE_BLOCK_DB=${block_db_part%?}"
      fi
      if [[ -L block.wal_dmcrypt ]]; then
        block_wal_part=$(resolve_symlink block.wal_dmcrypt)
        DOCKER_ENV="$DOCKER_ENV -e OSD_BLUESTORE_BLOCK_WAL=${block_wal_part%?}"
      elif [[ -L block.wal ]]; then
        block_wal_part=$(resolve_symlink block.wal)
        DOCKER_ENV="$DOCKER_ENV -e OSD_BLUESTORE_BLOCK_WAL=${block_wal_part%?}"
      fi
    else
      log "ERROR: unrecognized OSD type: $osd_type"
    fi
    echo "$DOCKER_ENV"
  fi

  cd || return
  umount_ceph_data "$mount_point"
  rmdir "$mount_point"
}

function start_disk_list () {
  mandatory_checks
  if is_dmcrypt; then
    # creates /dev/mapper/<uuid> for dmcrypt
    # usually after a reboot they don't go created
    udevadm trigger

    # latest versions of ceph-disk (after bluestore) put the lockbox partition on 5
    # where already deployed clusters with an earlier version of ceph-disk will do that
    # on partition 3
    local lock_partition_num=5
    if [ ! -b "$(dev_part "${OSD_DEVICE}" $lock_partition_num)" ]; then
      lock_partition_num=3
    fi
    lockbox_uuid=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" $lock_partition_num)")
    data_uuid=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
    data_part=$(dev_part "${OSD_DEVICE}" 1)
    mount_lockbox "$data_uuid" "$lockbox_uuid" 1> /dev/null
    if [[ ! -e /dev/mapper/"${data_uuid}" ]]; then
      open_encrypted_part "${data_uuid}" "${data_part}" "${data_uuid}" 1> /dev/null
    fi
    if [[ -n "$DISK_LIST_SEARCH" ]]; then
      get_docker_env "$DISK_LIST_SEARCH"
    else
      get_docker_env
    fi
    close_encrypted_part "${data_uuid}" "${data_part}" "${data_uuid}" 1> /dev/null
    umount_lockbox "$lockbox_uuid" 1> /dev/null
  else
    # this means we called this from osd_activate and that we are asking for a specific dev
    # the idea is to pass as a variable the 'type' we are looking for and we get the partition back
    # e.g: start_disk_list journal, will return /dev/sda2
    if [[ -n $DISK_LIST_SEARCH ]]; then
      get_docker_env "$DISK_LIST_SEARCH"
    else
      get_docker_env
    fi
  fi
}
