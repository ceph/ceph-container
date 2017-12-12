#!/bin/bash


###################################
# LIST OF ALL SCENARIOS AVAILABLE #
###################################

ALL_SCENARIOS="populate_kvstore mon osd osd_directory osd_directory_single osd_ceph_disk osd_ceph_disk_prepare osd_ceph_disk_activate osd_ceph_activate_journal mds rgw rgw_user restapi nfs zap_device mon_health mgr disk_introspection demo disk_list"


#########################
# LIST OF ALL VARIABLES #
#########################

: "${CLUSTER:=ceph}"
: "${CLUSTER_PATH:=ceph-config/${CLUSTER}}" # For KV config
: "${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}"
: "${CEPH_DAEMON:=${1}}" # default daemon to first argument
: "${CEPH_GET_ADMIN_KEY:=0}"
: "${HOSTNAME:=$(hostname -s)}"
: "${MON_NAME:=${HOSTNAME}}"
: "${MON_DATA_DIR:=/var/lib/ceph/mon/${CLUSTER}-${MON_NAME}}"
: "${K8S_HOST_NETWORK:=0}"
: "${K8S_MON_SELECTOR:=app=ceph,daemon=mon}"
: "${NETWORK_AUTO_DETECT:=0}"
: "${MDS_NAME:=${HOSTNAME}}"
: "${OSD_JOURNAL_SIZE:=100}"
: "${OSD_BLUESTORE:=1}"
: "${OSD_FILESTORE:=0}"
: "${OSD_BLUESTORE_BLOCK_UUID:=$(uuidgen)}"
: "${OSD_BLUESTORE_BLOCK_DB:=$OSD_DEVICE}"
: "${OSD_BLUESTORE_BLOCK_DB_UUID:=$(uuidgen)}"
: "${OSD_BLUESTORE_BLOCK_WAL:=$OSD_DEVICE}"
: "${OSD_BLUESTORE_BLOCK_WAL_UUID:=$(uuidgen)}"
: "${OSD_DMCRYPT:=0}"
: "${OSD_JOURNAL_UUID:=$(uuidgen)}"
: "${OSD_LOCKBOX_UUID:=$(uuidgen)}"
: "${CEPHFS_CREATE:=0}"
: "${CEPHFS_NAME:=cephfs}"
: "${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}"
: "${CEPHFS_DATA_POOL_PG:=8}"
: "${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}"
: "${CEPHFS_METADATA_POOL_PG:=8}"
: "${RGW_NAME:=${HOSTNAME}}"
: "${RBD_MIRROR_NAME:=${HOSTNAME}}"
: "${RGW_ZONEGROUP:=}"
: "${RGW_ZONE:=}"
: "${RGW_CIVETWEB_IP:=0.0.0.0}"
: "${RGW_CIVETWEB_PORT:=8080}"
: "${RGW_REMOTE_CGI:=0}"
: "${RGW_REMOTE_CGI_PORT:=9000}"
: "${RGW_REMOTE_CGI_HOST:=0.0.0.0}"
: "${RGW_USER:="cephnfs"}"
: "${RESTAPI_IP:=0.0.0.0}"
: "${RESTAPI_PORT:=5000}"
: "${RESTAPI_BASE_URL:=/api/v0.1}"
: "${RESTAPI_LOG_LEVEL:=warning}"
: "${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}"
: "${KV_TYPE:=none}" # valid options: etcd, k8s|kubernetes or none
: "${KV_IP:=127.0.0.1}"
: "${KV_PORT:=2379}"
: "${GANESHA_OPTIONS:=""}"
: "${GANESHA_EPOCH:=""}" # For restarting
: "${MGR_NAME:=${HOSTNAME}}"
: "${MGR_IP:=0.0.0.0}"

# Make sure to change the value of one another if user changes some of the default values
while read -r line; do
  if [[ "$line" == "OSD_FILESTORE=1" ]]; then
    OSD_BLUESTORE=0
  elif [[ "$line" == "OSD_BLUESTORE=1" ]]; then
    OSD_FILESTORE=0
  fi
done < <(env)

# Create a default array
CRUSH_LOCATION_DEFAULT=("root=default" "host=${HOSTNAME}")
[[ -n "$CRUSH_LOCATION" ]] || read -ra CRUSH_LOCATION <<< "${CRUSH_LOCATION_DEFAULT[@]}"

# This is ONLY used for the CLI calls, e.g: ceph $CLI_OPTS health
CLI_OPTS=(--cluster ${CLUSTER})

# This is ONLY used for the daemon's startup, e.g: ceph-osd $DAEMON_OPTS
DAEMON_OPTS=(--cluster ${CLUSTER} --setuser ceph --setgroup ceph -d)

MOUNT_OPTS=(-t xfs -o noatime,inode64)

# make sure etcd uses http or https as a prefix
if [[ "$KV_TYPE" == "etcd" ]]; then
  if [ -n "${KV_CA_CERT}" ]; then
    CONFD_NODE_SCHEMA="https://"
    KV_TLS=(--ca-file=${KV_CA_CERT} --cert-file=${KV_CLIENT_CERT} --key-file=${KV_CLIENT_KEY})
    CONFD_KV_TLS=(-scheme=https -client-ca-keys=${KV_CA_CERT} -client-cert=${KV_CLIENT_CERT} -client-key=${KV_CLIENT_KEY})
  else
    CONFD_NODE_SCHEMA="http://"
  fi
  ETCD_SCHEMA=${CONFD_NODE_SCHEMA}
  ETCDCTL_OPTS=(--peers ${ETCD_SCHEMA}${KV_IP}:${KV_PORT})
fi

# Internal variables
MDS_KEYRING=/var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring
ADMIN_KEYRING=/etc/ceph/${CLUSTER}.client.admin.keyring
MON_KEYRING=/etc/ceph/${CLUSTER}.mon.keyring
RGW_KEYRING=/var/lib/ceph/radosgw/${CLUSTER}-rgw.${RGW_NAME}/keyring
MDS_BOOTSTRAP_KEYRING=/var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
RGW_BOOTSTRAP_KEYRING=/var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring
OSD_BOOTSTRAP_KEYRING=/var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
RBD_MIRROR_BOOTSTRAP_KEYRING=/var/lib/ceph/bootstrap-rbd/${CLUSTER}.keyring
OSD_PATH_BASE=/var/lib/ceph/osd/${CLUSTER}
MONMAP=/etc/ceph/monmap-${CLUSTER}
MGR_KEYRING=/var/lib/ceph/mgr/${CLUSTER}-${MGR_NAME}/keyring
RBD_MIRROR_KEYRING=/etc/ceph/${CLUSTER}.client.rbd-mirror.${HOSTNAME}.keyring
