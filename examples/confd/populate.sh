#!/bin/bash
#populate the KV store with ceph.conf parameters
set -x

CLUSTER="ceph"
KV_IP="127.0.0.1"
KV_PORT="2379"
CLUSTER_PATH=ceph-config/${CLUSTER}
ETCDCTL_OPT="--peers ${KV_IP}:${KV_PORT}"

# Optional TLS settings
#KV_CA_CERT=/path/to/ssl/ca-cert.pem
#KV_CLIENT_CERT=/path/to/ssl/client-cert.pem
#KV_CLIENT_KEY=/path/to/ssl/client-key.pem

if [ -n "${KV_CA_CERT}" ]; then
	KV_TLS="--ca-cert=${KV_CA_CERT} --client-cert=${KV_CLIENT_CERT} --client-key=${KV_CLIENT_KEY}"
fi

# auth
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/auth/cephx true
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/auth/cephx_require_signatures false
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/auth/cephx_cluster_require_signatures true
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/auth/cephx_service_require_signatures false

# auth
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/max_open_files 131072
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/osd_pool_default_pg_num 128
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/osd_pool_default_pgp_num 128
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/osd_pool_default_size 3
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/osd_pool_default_min_size 1

etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/mon_osd_full_ratio .95
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/global/mon_osd_nearfull_ratio .85

#mon
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon/mon_osd_down_out_interval 600
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon/mon_osd_min_down_reporters 4
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon/mon_clock_drift_allowed .15
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon/mon_clock_drift_warn_backoff 30
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon/mon_osd_report_timeout 300

#osd
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_journal_size 100
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/cluster_network 192.168.42.0/24
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/public_network 192.168.42.0/24
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_mkfs_type xfs
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_mkfs_options_xfs "-f -i size=2048"
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_mon_heartbeat_interval 30

#crush
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/pool_default_crush_rule 0
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_crush_update_on_start true

#backend
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_objectstore filestore

#performance tuning
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/filestore_merge_threshold 40
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/filestore_split_multiple 8
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_op_threads 8
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/filestore_op_threads 8
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/filestore_max_sync_interval 5
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_max_scrubs 1

#recovery tuning
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_recovery_max_active 5
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_max_backfills 2
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_recovery_op_priority 2
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_client_op_priority 63
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_recovery_max_chunk 1048576
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/osd_recovery_threads 1

#ports
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/ms_bind_port_min 6800
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/osd/ms_bind_port_max 7100

#client
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/client/rbd_cache_enabled true
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/client/rbd_cache_writethrough_until_flush true

#mds
etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mds/mds_cache_size 100000
