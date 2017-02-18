: ${CLUSTER:=ceph}
: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}
: ${CEPH_DAEMON:=${1}} # default daemon to first argument
: ${CEPH_GET_ADMIN_KEY:=0}
: ${HOSTNAME:=$(hostname -s)}
: ${MON_NAME:=${HOSTNAME}}
: ${MON_DATA_DIR:=/var/lib/ceph/mon/${CLUSTER}-${MON_NAME}}
: ${NETWORK_AUTO_DETECT:=0}
: ${MDS_NAME:=mds-${HOSTNAME}}
: ${OSD_FORCE_ZAP:=0}
: ${OSD_JOURNAL_SIZE:=100}
: ${OSD_BLUESTORE:=0}
: ${OSD_DMCRYPT:=0}
: ${OSD_JOURNAL_UUID:=$(uuidgen)}
: ${OSD_LOCKBOX_UUID:=$(uuidgen)}
: ${CRUSH_LOCATION:=root=default host=${HOSTNAME}}
: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}
: ${RGW_NAME:=${HOSTNAME}}
: ${RGW_ZONEGROUP:=}
: ${RGW_ZONE:=}
: ${RGW_CIVETWEB_PORT:=8080}
: ${RGW_REMOTE_CGI:=0}
: ${RGW_REMOTE_CGI_PORT:=9000}
: ${RGW_REMOTE_CGI_HOST:=0.0.0.0}
: ${RGW_USER:="cephnfs"}
: ${RESTAPI_IP:=0.0.0.0}
: ${RESTAPI_PORT:=5000}
: ${RESTAPI_BASE_URL:=/api/v0.1}
: ${RESTAPI_LOG_LEVEL:=warning}
: ${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}
: ${KV_TYPE:=none} # valid options: consul, etcd or none
: ${KV_IP:=127.0.0.1}
: ${KV_PORT:=4001} # PORT 8500 for Consul
: ${GANESHA_OPTIONS:=""}
: ${GANESHA_EPOCH:=""} # For restarting

if [ ! -z "${KV_CA_CERT}" ]; then
  KV_TLS="--ca-cert=${KV_CA_CERT} --client-cert=${KV_CLIENT_CERT} --client-key=${KV_CLIENT_KEY}"
  CONFD_KV_TLS="-scheme=https -client-ca-keys=${KV_CA_CERT} -client-cert=${KV_CLIENT_CERT} -client-key=${KV_CLIENT_KEY}"
fi

CEPH_OPTS="--cluster ${CLUSTER}"
MOUNT_OPTS="-t xfs -o noatime,inode64"
