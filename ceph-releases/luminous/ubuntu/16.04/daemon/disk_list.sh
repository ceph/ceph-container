#!/bin/bash
set -e


#############
# VARIABLES #
#############

tmp_dir="$(mktemp --directory --tmpdir=/var/lib/ceph/tmp/)"
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

function is_dmcrypt () {
  blkid -t TYPE=crypto_LUKS "${OSD_DEVICE}1" -o value -s PARTUUID &> /dev/null
}

function mount_ceph_data () {
  if is_dmcrypt; then
    mount /dev/mapper/"${data_uuid}" "$tmp_dir"
  else
    mount "${OSD_DEVICE}1" "$tmp_dir"
  fi
}

function umount_ceph_data () {
  umount "$tmp_dir"
}

function get_docker_env () {
  mount_ceph_data
  cd "$tmp_dir" || return
  if [[ -n "${1}" ]]; then
    if is_dmcrypt; then
      cd /var/lib/ceph/osd-lockbox/"$data_uuid"
    fi
    if [[ -L "${1}" ]]; then
      resolve_symlink "${1}"
    elif [[ -f "${1}" ]]; then
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
  umount_ceph_data
}

function start_disk_list () {
  mandatory_checks
  if is_dmcrypt; then
    # creates /dev/mapper/<uuid> for dmcrypt
    # usually after a reboot they don't go created
    udevadm trigger

    lockbox_uuid=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 5)")
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
    if [[ -n "$DISK_LIST_SEARCH" ]]; then
      get_docker_env "$DISK_LIST_SEARCH"
    else
      get_docker_env
    fi
  fi
}
