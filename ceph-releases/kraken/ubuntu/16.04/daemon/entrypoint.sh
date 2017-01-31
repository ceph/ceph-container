#!/bin/bash
set -e

source variables_entrypoint.sh
source common_functions.sh

###########################
# CONFIGURATION GENERATOR #
###########################

# Load in the bootstrapping routines
# based on the data store
case "$KV_TYPE" in
   etcd|consul)
      source /config.kv.sh
      ;;
   k8s|kubernetes)
      source /config.k8s.sh
      ;;

   *)
      source /config.static.sh
      ;;
esac


###############
# CEPH_DAEMON #
###############

# Normalize DAEMON to lowercase
CEPH_DAEMON=$(echo ${CEPH_DAEMON} |tr '[:upper:]' '[:lower:]')

# If we are given a valid first argument, set the
# CEPH_DAEMON variable from it
case "$CEPH_DAEMON" in
  populate_kvstore)
    source populate_kv.sh
    populate_kv
    ;;
  mon)
    source start_mon.sh
    start_mon
    ;;
  osd)
    source start_osd.sh
    start_osd
    ;;
  osd_directory)
    source start_osd.sh
    OSD_TYPE="directory"
    start_osd
    ;;
  osd_directory_single)
    source start_osd.sh
    OSD_TYPE="directory_single"
    start_osd
    ;;
  osd_ceph_disk)
    source start_osd.sh
    OSD_TYPE="disk"
    start_osd
    ;;
  osd_ceph_disk_prepare)
    source start_osd.sh
    OSD_TYPE="prepare"
    start_osd
    ;;
  osd_ceph_disk_activate)
    source start_osd.sh
    OSD_TYPE="activate"
    start_osd
    ;;
  osd_ceph_activate_journal)
    source start_osd.sh
    OSD_TYPE="activate_journal"
    start_osd
    ;;
  mds)
    source start_mds.sh
    start_mds
    ;;
  rgw)
    source start_rgw.sh
    start_rgw
    ;;
  rgw_user)
    source start_rgw.sh
    create_rgw_user
    ;;
  restapi)
    source start_restapi.sh
    start_restapi
    ;;
  rbd_mirror)
    source start_rbd_mirror.sh
    start_rbd_mirror
    ;;
  nfs)
    source start_nfs.sh
    start_nfs
    ;;
  zap_device)
    source zap_device.sh
    zap_device
    ;;
  mon_health)
    source watch_mon_health.sh
    watch_mon_health
    ;;
  *)
  if [ ! -n "$CEPH_DAEMON" ]; then
    log "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name "
    log "of the daemon you want to deploy."
    log "Valid values for CEPH_DAEMON are MON, OSD, OSD_DIRECTORY, OSD_CEPH_DISK, OSD_CEPH_DISK_PREPARE, OSD_CEPH_DISK_ACTIVATE, OSD_CEPH_ACTIVATE_JOURNAL, MDS, RGW, RGW_USER, RESTAPI, ZAP_DEVICE, RBD_MIRROR, NFS"
    log "Valid values for the daemon parameter are mon, osd, osd_directory, osd_ceph_disk, osd_ceph_disk_prepare, osd_ceph_disk_activate, osd_ceph_activate_journal, mds, rgw, rgw_user, restapi, zap_device, rbd_mirror, nfs"
    exit 1
  fi
  ;;
esac

exit 0
