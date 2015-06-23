#!/bin/bash
#populate the KV store with ceph.conf parameters
set -x
 
CLUSTER="ceph"
KV="consul"
IP="127.0.0.1"
PORT="8500"
CLUSTER_PATH=ceph-config/${CLUSTER}

#ceph-common
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/common/cephx true
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/common/cephx_require_signatures false
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/common/cephx_cluster_require_signatures true
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/common/cephx_service_require_signatures false
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/common/max_open_files 131072
 
#monitor
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_osd_down_out_interval 600
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_osd_min_down_reporters 4
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_clock_drift_allowed .15
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_clock_drift_warn_backoff 30
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_osd_full_ratio .95
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_osd_nearfull_ratio .85
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/mon/mon_osd_report_timeout 300
 
#osd
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/journal_size 100
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/pool_default_pg_num 128
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/pool_default_pgp_num 128
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/pool_default_size 3
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/pool_default_min_size 1
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/cluster_network 192.168.42.0/24
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/public_network 192.168.42.0/24
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/osd_mkfs_type xfs
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/osd_mkfs_options_xfs "-f -i size=2048"
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/osd_mount_options_xfs noatime,largeio,inode,swalloc
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/osd/osd_mon_heartbeat_interval 30
 
#crush
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/crush/pool_default_crush_rule 0
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/crush/osd_crush_update_on_start true
 
#backend
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/backend/osd_objectstore filestore
 
#performance tuning
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/filestore_merge_threshold 40
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/filestore_split_multiple 8
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/osd_op_threads 8
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/filestore_op_threads 8
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/filestore_max_sync_interval 5
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/perf/osd_max_scrubs 1
 
#recovery tuning
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_recovery_max_active 5
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_max_backfills 2
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_recovery_op_priority 2
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_client_op_priority 63
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_recovery_max_chunk 1048576
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rec/osd_recovery_threads 1
 
#ports
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/ports/mon_port 6789
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/ports/ms_bind_port_min 6800
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/ports/ms_bind_port_max 7100
 
 
#rbd
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rbd/rbd_cache_enabled true
kviator --kvstore=${KV} --client=${IP}:${PORT} put ${CLUSTER_PATH}/rbd/rbd_cache_writethrough_until_flush true