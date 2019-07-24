#!/bin/bash
set -e

if is_redhat; then
  if [[ -n "${TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES}" ]]; then
    sed -i -e "s/^\(TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES\)=.*/\1=${TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES}/" /etc/sysconfig/ceph
  fi
  source /etc/sysconfig/ceph
fi

function start_osd {
  get_config
  check_config

  if [ "${CEPH_GET_ADMIN_KEY}" -eq 1 ]; then
    get_admin_key
    check_admin_key
  fi

  case "$OSD_TYPE" in
    directory)
      source osd_directory.sh
      source osd_common.sh
      osd_directory
      ;;
    directory_single)
      source osd_directory_single.sh
      osd_directory_single
      ;;
    disk)
      osd_disk
      ;;
    prepare)
      source osd_disk_prepare.sh
      osd_disk_prepare
      ;;
    activate)
      source osd_disk_activate.sh
      osd_activate
      ;;
    activate_only)
      source osd_disk_activate.sh
      osd_activate no_start
      ;;
    devices)
      source osd_disks.sh
      source osd_common.sh
      osd_disks
      ;;
    activate_journal)
      source osd_activate_journal.sh
      source osd_common.sh
      osd_activate_journal
      ;;
    *)
      osd_trying_to_determine_scenario
      ;;
  esac
}

function osd_disk {
  source osd_disk_prepare.sh
  source osd_disk_activate.sh
  osd_disk_prepare
  osd_activate
}
