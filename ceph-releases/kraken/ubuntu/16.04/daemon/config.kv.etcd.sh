#!/bin/bash
set -e

sed -r "s/@CLUSTER@/${CLUSTER:-ceph}/g" \
    /etc/confd/conf.d/ceph.conf.toml.in > /etc/confd/conf.d/ceph.conf.toml

function get_mon_config {
  # Make sure root dirs are present for confd to work
  for dir in auth global mon mds osd client; do
    etcdctl $ETCDCTL_OPT ${KV_TLS} mkdir ${CLUSTER_PATH}/$dir > /dev/null 2>&1  || log "'$dir' key already exists"
  done

  log "Adding Mon Host - ${MON_NAME}."
  etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/mon_host/${MON_NAME} ${MON_IP}

  # Acquire lock to not run into race conditions with parallel bootstraps
  until etcdctl $ETCDCTL_OPT ${KV_TLS} mk ${CLUSTER_PATH}/lock $MON_NAME; do
    log "Configuration is locked by another host. Waiting..."
    sleep 1
  done

  # Update config after initial mon creation
  if etcdctl $ETCDCTL_OPT ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete; then
    log "Configuration found for cluster ${CLUSTER}. Writing to disk."

    get_config

    log "Adding mon/admin Keyrings."
    etcdctl $ETCDCTL_OPT ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
    etcdctl $ETCDCTL_OPT ${KV_TLS} get ${CLUSTER_PATH}/monKeyring > /etc/ceph/${CLUSTER}.mon.keyring

    if [ ! -f /etc/ceph/monmap-${CLUSTER} ]; then
      log "Monmap is missing. Adding initial monmap..."
      etcdctl $ETCDCTL_OPT ${KV_TLS} get ${CLUSTER_PATH}/monmap | uudecode -o /etc/ceph/monmap-${CLUSTER}
    fi

    log "Trying to get the most recent monmap..."
    if timeout 5 ceph ${CEPH_OPTS} mon getmap -o /etc/ceph/monmap-${CLUSTER}; then
      log "Monmap successfully retrieved. Updating KV store."
      uuencode /etc/ceph/monmap-${CLUSTER} | etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/monmap
    else
      log "Peers not found, using initial monmap."
    fi

  else
    # Create initial Mon, keyring
    log "No configuration found for cluster ${CLUSTER}. Generating."

    local fsid=$(uuidgen)
    etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/auth/fsid ${fsid}

    until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/"; do
      log "Waiting for confd to write initial templates..."
      sleep 1
    done

    log "Creating Keyrings."
    ceph-authtool /etc/ceph/${CLUSTER}.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    ceph-authtool /etc/ceph/${CLUSTER}.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'
    for daemon in osd mds rgw; do
      ceph-authtool /var/lib/ceph/bootstrap-$daemon/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-$daemon --cap mon "allow profile bootstrap-$daemon"
    done

    log "Creating Monmap."
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${fsid} /etc/ceph/monmap-${CLUSTER}

    log "Importing Keyrings and Monmap to KV."
    etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/monKeyring < /etc/ceph/${CLUSTER}.mon.keyring
    etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/adminKeyring < /etc/ceph/${CLUSTER}.client.admin.keyring
    for bootstrap in Osd Mds Rgw; do
      etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/bootstrap${bootstrap}Keyring < /var/lib/ceph/bootstrap-$(to_lowercase $bootstrap)/${CLUSTER}.keyring
    done
    uuencode /etc/ceph/monmap-${CLUSTER} - | etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/monmap

    log "Completed initialization for ${MON_NAME}."
    etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/monSetupComplete true
  fi

  # Remove lock for other clients to install
  log "Removing lock for ${MON_NAME}."
  etcdctl $ETCDCTL_OPT ${KV_TLS} rm ${CLUSTER_PATH}/lock
}

function get_config {
  until etcdctl $ETCDCTL_OPT ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete; do
    log "OSD: Waiting for monitor setup to complete..."
    sleep 5
  done

  until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
    log "Waiting for confd to update templates..."
    sleep 1
  done

  log "Adding bootstrap keyrings."
  for bootstrap in Osd Mds Rgw; do
    etcdctl $ETCDCTL_OPT ${KV_TLS} set ${CLUSTER_PATH}/bootstrap${bootstrap}Keyring < /var/lib/ceph/bootstrap-$(to_lowercase $bootstrap)/${CLUSTER}.keyring
  done
}
