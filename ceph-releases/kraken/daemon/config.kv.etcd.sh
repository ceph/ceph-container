#!/bin/bash
set -e

sed -r "s/@CLUSTER@/${CLUSTER:-ceph}/g" \
    /etc/confd/conf.d/ceph.conf.toml.in > /etc/confd/conf.d/ceph.conf.toml

function get_mon_config {
  # Make sure root dirs are present for confd to work
  for dir in auth global mon mds osd client; do
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" mkdir "${CLUSTER_PATH}"/"$dir" > /dev/null 2>&1  || log "'$dir' key already exists"
  done

  log "Adding Mon Host - ${MON_NAME}."
  etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/mon_host/"${MON_NAME}" "${MON_IP}"

  # Acquire lock to not run into race conditions with parallel bootstraps
  until etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" mk "${CLUSTER_PATH}"/lock "$MON_NAME" --ttl 60; do
    log "Configuration is locked by another host. Waiting..."
    sleep 1
  done

  # Update config after initial mon creation
  if etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/monSetupComplete; then
    log "Configuration found for cluster ${CLUSTER}. Writing to disk."

    get_config

    log "Adding mon/admin Keyrings."
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/adminKeyring > "$ADMIN_KEYRING"
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/monKeyring > "$MON_KEYRING"

    if [ ! -f "$MONMAP" ]; then
      log "Monmap is missing. Adding initial monmap..."
      etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/monmap | uudecode -o "$MONMAP"
    fi

    log "Trying to get the most recent monmap..."
    if timeout 5 ceph "${CLI_OPTS[@]}" mon getmap -o "$MONMAP"; then
      log "Monmap successfully retrieved. Updating KV store."
      uuencode "$MONMAP" - | etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/monmap
    else
      log "Peers not found, using initial monmap."
    fi

  else
    # Create initial Mon, keyring
    log "No configuration found for cluster ${CLUSTER}. Generating."

    local fsid
    fsid=$(uuidgen)
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/auth/fsid "${fsid}"

    until confd -onetime -backend "${KV_TYPE}" -node "${CONFD_NODE_SCHEMA}""${KV_IP}":"${KV_PORT}" "${CONFD_KV_TLS[@]}" -prefix="/${CLUSTER_PATH}/"; do
      log "Waiting for confd to write initial templates..."
      sleep 1
    done

    log "Creating Keyrings."
    if [ -z "$ADMIN_SECRET" ]; then
      # Automatically generate administrator key
      CLI+=(--gen-key)
    else
      # Generate custom provided administrator key
      CLI+=("--add-key=$ADMIN_SECRET")
    fi
    ceph-authtool "$ADMIN_KEYRING" --create-keyring "${CLI[@]}" -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    ceph-authtool "$MON_KEYRING" --create-keyring --gen-key -n mon. --cap mon 'allow *'

    for item in ${OSD_BOOTSTRAP_KEYRING}:Osd ${MDS_BOOTSTRAP_KEYRING}:Mds ${RGW_BOOTSTRAP_KEYRING}:Rgw; do
      local array
      IFS=" " read -r -a array <<< "${item//:/ }"
      local keyring=${array[0]}
      local bootstrap="bootstrap-${array[1]}"
      ceph-authtool "$keyring" --create-keyring --gen-key -n client."$(to_lowercase "$bootstrap")" --cap mon "allow profile $(to_lowercase "$bootstrap")"
      bootstrap="bootstrap${array[1]}Keyring"
      etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/"${bootstrap}" < "$keyring"
    done

    log "Creating Monmap."
    monmaptool --create --add "${MON_NAME}" "${MON_IP}:6789" --fsid "${fsid}" "$MONMAP"

    log "Importing Keyrings and Monmap to KV."
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/monKeyring < "$MON_KEYRING"
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/adminKeyring < "$ADMIN_KEYRING"
    chown --verbose ceph. "$MON_KEYRING" "$ADMIN_KEYRING"

    uuencode "$MONMAP" - | etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/monmap

    log "Completed initialization for ${MON_NAME}."
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/monSetupComplete true
  fi

  # Remove lock for other clients to install
  log "Removing lock for ${MON_NAME}."
  etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" rm "${CLUSTER_PATH}"/lock
}

function import_bootstrap_keyrings {
  for item in ${OSD_BOOTSTRAP_KEYRING}:Osd ${MDS_BOOTSTRAP_KEYRING}:Mds ${RGW_BOOTSTRAP_KEYRING}:Rgw; do
    local array
    IFS=" " read -r -a array <<< "${item//:/ }"
    local keyring
    keyring=${array[0]}
    local bootstrap_keyring
    bootstrap_keyring="bootstrap${array[1]}Keyring"
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/"${bootstrap_keyring}" > "$keyring"
    chown --verbose ceph. "$keyring"
  done
}

function get_config {
  until etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/monSetupComplete; do
    log "OSD: Waiting for monitor setup to complete..."
    sleep 5
  done

  until confd -onetime -backend "${KV_TYPE}" -node "${CONFD_NODE_SCHEMA}""${KV_IP}":"${KV_PORT}" "${CONFD_KV_TLS[@]}" -prefix="/${CLUSTER_PATH}/"; do
    log "Waiting for confd to update templates..."
    sleep 1
  done

  log "Adding bootstrap keyrings."
  import_bootstrap_keyrings
}

function get_admin_key {
  log "Retrieving the admin key."
  etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/adminKeyring > /etc/ceph/"${CLUSTER}".client.admin.keyring
}
