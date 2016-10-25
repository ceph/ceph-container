#!/bin/bash
set -e 

# CONFIG_ROOT - etcd root for ceph-related keys
: ${CONFIG_ROOT:=/ceph}

# CLUSTER - name of ceph cluster
: ${CLUSTER:=ceph}

# CLUSTER_PATH - etcd path where configuration should be stored
: ${CLUSTER_PATH:=${CONFIG_ROOT}/${CLUSTER}/config}

# ETCDCTL_PEERS - where to find etcd peers
: ${ETCDCTL_PEERS:=${COREOS_PUBLIC_IPV4}}

if [ ! -n "$MON_NAME" ]; then
  echo >&2 "ERROR: MON_NAME must be defined as the name of the monitor"
  exit 1
fi
 
if [ ! -n "$MON_IP" ]; then
  echo >&2 "ERROR: MON_IP must be defined as the IP address of the monitor"
  exit 1
fi

if [ ! -n "$ETCDCTL_PEERS" ]; then
  echo >&2 "ERROR: ETCDCTL_PEERS must be defined"
  exit 1
fi
 
if [ -e /etc/ceph/ceph.conf ]; then
  echo "Found existing config. Done."
  exit 0
fi

# Change to the old CLUSTER_PATH, if it already exists
set +e
etcdctl get /ceph-config/${CLUSTER}/done 2>/dev/null
RET=$?
set -e
if [ $RET -eq 0 ]; then
   echo "Old configuration key (/ceph-config/) found; using it instead"
   CLUSTER_PATH=/ceph-config/${CLUSTER}
fi
 
# Acquire lock to not run into race conditions with parallel bootstraps
until etcdctl mk ${CLUSTER_PATH}/lock $MON_NAME --ttl 60 > /dev/null 2>&1 ; do
  echo "Configuration is locked by another host. Waiting."
  sleep 1
done

# Don't cancel this script when the `done` key doesn't exist
set +e
etcdctl get ${CLUSTER_PATH}/done 2>/dev/null >/dev/null
RET=$?
set -e
if [ $RET -eq 0 ]; then
  echo "Configuration found for cluster ${CLUSTER}. Writing to disk."

  etcdctl get ${CLUSTER_PATH}/ceph.conf > /etc/ceph/ceph.conf
  etcdctl get ${CLUSTER_PATH}/ceph.mon.keyring > /etc/ceph/ceph.mon.keyring
  etcdctl get ${CLUSTER_PATH}/ceph.client.admin.keyring > /etc/ceph/ceph.client.admin.keyring

  echo "Attempting to pull monitor map from existing cluster."
  ceph mon getmap -o /etc/ceph/monmap-${CLUSTER}
else
  echo "No configuration found for cluster ${CLUSTER}. Generating."

  fsid=$(uuidgen)
  cat <<ENDHERE >/etc/ceph/ceph.conf
fsid = $fsid
mon initial members = ${MON_NAME}
mon host = ${MON_IP}
auth cluster required = cephx
auth service required = cephx
auth client required = cephx
ENDHERE

  ceph-authtool /etc/ceph/ceph.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
  ceph-authtool /etc/ceph/ceph.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'
  monmaptool --create --add ${MON_NAME} ${MON_IP} --fsid ${fsid}  /etc/ceph/monmap-${CLUSTER}

  etcdctl set ${CLUSTER_PATH}/ceph.conf < /etc/ceph/ceph.conf > /dev/null
  etcdctl set ${CLUSTER_PATH}/ceph.mon.keyring < /etc/ceph/ceph.mon.keyring > /dev/null
  etcdctl set ${CLUSTER_PATH}/ceph.client.admin.keyring < /etc/ceph/ceph.client.admin.keyring > /dev/null
    
  echo "completed initialization for ${MON_NAME}"
  etcdctl set ${CLUSTER_PATH}/done true > /dev/null 2>&1
fi

echo "unlocking configuration"
etcdctl rm ${CLUSTER_PATH}/lock > /dev/null 2>&1

