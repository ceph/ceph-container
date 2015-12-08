#!/bin/bash
#populate the KV store with ceph.conf parameters
set -x

#CLUSTER="ceph"
#KV="etcd"
#IP="127.0.0.1"
#PORT="4001"
CLUSTER_PATH=ceph-config/${CLUSTER}
# Note the 'cas' command puts a value in the KV store if it is empty

# auth
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/auth/cephx true || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/auth/cephx_require_signatures false || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/auth/cephx_cluster_require_signatures true || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/auth/cephx_service_require_signatures false || echo "value is already set"

# auth
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/max_open_files 131072 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/osd_pool_default_pg_num 128 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/osd_pool_default_pgp_num 128 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/osd_pool_default_size 3 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/osd_pool_default_min_size 1 || echo "value is already set"

kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/mon_osd_full_ratio .95 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/global/mon_osd_nearfull_ratio .85 || echo "value is already set"

#mon
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon/mon_osd_down_out_interval 600 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon/mon_osd_min_down_reporters 4 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon/mon_clock_drift_allowed .15 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon/mon_clock_drift_warn_backoff 30 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon/mon_osd_report_timeout 300 || echo "value is already set"

#osd
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/journal_size 100 || echo "value is already set"

# these 2 should be passed at runtime to the container.
#kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/cluster_network 198.100.128.0/19 || echo "value is already set"
#kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/public_network 198.100.128.0/19 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_mkfs_type xfs || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_mkfs_options_xfs "-f -i size=2048" || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_mon_heartbeat_interval 30 || echo "value is already set"

#crush
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/pool_default_crush_rule 0 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_crush_update_on_start true || echo "value is already set"

#backend
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_objectstore filestore || echo "value is already set"

#performance tuning
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/filestore_merge_threshold 40 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/filestore_split_multiple 8 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_op_threads 8 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/filestore_op_threads 8 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/filestore_max_sync_interval 5 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_max_scrubs 1 || echo "value is already set"

#recovery tuning
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_recovery_max_active 5 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_max_backfills 2 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_recovery_op_priority 2 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_client_op_priority 63 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_recovery_max_chunk 1048576 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/osd_recovery_threads 1 || echo "value is already set"

#ports
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/ms_bind_port_min 6800 || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/osd/ms_bind_port_max 7100 || echo "value is already set"

#client
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/client/rbd_cache_enabled true || echo "value is already set"
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/client/rbd_cache_writethrough_until_flush true || echo "value is already set"

#mds
kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mds/mds_cache_size 100000 || echo "value is already set"

set +x