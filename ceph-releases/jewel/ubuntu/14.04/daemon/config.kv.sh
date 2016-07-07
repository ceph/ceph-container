#!/bin/bash
set -e

sed -r "s/@CLUSTER@/${CLUSTER:-ceph}/g" \
    /etc/confd/conf.d/ceph.conf.toml.in > /etc/confd/conf.d/ceph.conf.toml

# make sure etcd uses http or https as a prefix
if [[ "$KV_TYPE" == "etcd" ]]; then
  if [ ! -z "${KV_CA_CERT}" ]; then
  	CONFD_NODE_SCHEMA="https://"
  else
    CONFD_NODE_SCHEMA="http://"
  fi
fi

function get_admin_key {
   kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
}


function get_mon_config {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  # making sure the root dirs are present for the confd to work with etcd
  if [[ "$KV_TYPE" == "etcd" ]]; then
    etcdctl mkdir ${CLUSTER_PATH}/auth > /dev/null 2>&1  || echo "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/global > /dev/null 2>&1  || echo "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/mon > /dev/null 2>&1  || echo "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/mds > /dev/null 2>&1  || echo "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/osd > /dev/null 2>&1  || echo "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/client > /dev/null 2>&1  || echo "key already exists"
  fi

  echo "Adding Mon Host - ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/mon_host/${MON_NAME} ${MON_IP} > /dev/null 2>&1

  # Acquire lock to not run into race conditions with parallel bootstraps
  until kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} cas ${CLUSTER_PATH}/lock $MON_NAME > /dev/null 2>&1 ; do
    echo "Configuration is locked by another host. Waiting."
    sleep 1
  done

  # Update config after initial mon creation
  if kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; then
    echo "Configuration found for cluster ${CLUSTER}. Writing to disk."


    until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
      echo "Waiting for confd to update templates..."
      sleep 1
    done

    # Check/Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    echo "Adding Keyrings"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monKeyring > /etc/ceph/${CLUSTER}.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapOsdKeyring > /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapMdsKeyring > /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapRgwKeyring > /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring


    if [ ! -f /etc/ceph/monmap ]; then
      echo "Monmap is missing. Adding initial monmap..."
      kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monmap | uudecode -o /etc/ceph/monmap
    fi

    echo "Trying to get the most recent monmap..."
    if timeout 5 ceph ${CEPH_OPTS} mon getmap -o /etc/ceph/monmap; then
      echo "Monmap successfully retrieved.  Updating KV store."
      uuencode /etc/ceph/monmap - | kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monmap -
    else
      echo "Peers not found, using initial monmap."
    fi

  else
    # Create initial Mon, keyring
    echo "No configuration found for cluster ${CLUSTER}. Generating."

    FSID=$(uuidgen)
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/auth/fsid ${FSID}

    until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
      echo "Waiting for confd to write initial templates..."
      sleep 1
    done

    echo "Creating Keyrings"
    ceph-authtool /etc/ceph/${CLUSTER}.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    ceph-authtool /etc/ceph/${CLUSTER}.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

    # Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    # Generate the OSD bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'

    # Generate the MDS bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'

    # Generate the RGW bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'


    echo "Creating Monmap"
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${FSID} /etc/ceph/monmap

    echo "Importing Keyrings and Monmap to KV"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monKeyring - < /etc/ceph/${CLUSTER}.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/adminKeyring - < /etc/ceph/${CLUSTER}.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapOsdKeyring - < /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapMdsKeyring - < /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapRgwKeyring - < /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring

    uuencode /etc/ceph/monmap - | kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monmap -

    echo "Completed initialization for ${MON_NAME}"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monSetupComplete true > /dev/null 2>&1
  fi

  # Remove lock for other clients to install
  echo "Removing lock for ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} del ${CLUSTER_PATH}/lock > /dev/null 2>&1

}

function get_config {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  until kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; do
    echo "OSD: Waiting for monitor setup to complete..."
    sleep 5
  done

  until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
    echo "Waiting for confd to update templates..."
    sleep 1
  done

  # Check/Create bootstrap key directories
  mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

  echo "Adding bootstrap keyrings"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapOsdKeyring > /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapMdsKeyring > /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapRgwKeyring > /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring

}
