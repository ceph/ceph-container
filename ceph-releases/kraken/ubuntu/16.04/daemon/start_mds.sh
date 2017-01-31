#!/bin/bash
set -e

function start_mds {
  get_config
  check_config
  create_socket_dir

  # Check to see if we are a new MDS
  if [ ! -e /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring ]; then

     mkdir -p /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}
     chown ceph. /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}

    if [ -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
       KEYRING_OPT="--name client.admin --keyring /etc/ceph/${CLUSTER}.client.admin.keyring"
    elif [ -e /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring ]; then
       KEYRING_OPT="--name client.bootstrap-mds --keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring"
    else
      log "ERROR- Failed to bootstrap MDS: could not find admin or bootstrap-mds keyring.  You can extract it from your current monitor by running 'ceph auth get client.bootstrap-mds -o /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring'"
      exit 1
    fi

    timeout 10 ceph ${CEPH_OPTS} $KEYRING_OPT health || exit 1

    # Generate the MDS key
    ceph ${CEPH_OPTS} $KEYRING_OPT auth get-or-create mds.$MDS_NAME osd 'allow rwx' mds 'allow' mon 'allow profile mds' -o /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring
    chown ceph. /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring
    chmod 600 /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring

  fi

  # NOTE (leseb): having the admin keyring is really a security issue
  # If we need to bootstrap a MDS we should probably create the following on the monitors
  # I understand that this handy to do this here
  # but having the admin key inside every container is a concern

  # Create the Ceph filesystem, if necessary
  if [ $CEPHFS_CREATE -eq 1 ]; then

    get_admin_key
    check_admin_key

    if [[ "$(ceph fs ls | grep -c name:.${CEPHFS_NAME},)" -eq "0" ]]; then
       # Make sure the specified data pool exists
       if ! ceph ${CEPH_OPTS} osd pool stats ${CEPHFS_DATA_POOL} > /dev/null 2>&1; then
          ceph ${CEPH_OPTS} osd pool create ${CEPHFS_DATA_POOL} ${CEPHFS_DATA_POOL_PG}
       fi

       # Make sure the specified metadata pool exists
       if ! ceph ${CEPH_OPTS} osd pool stats ${CEPHFS_METADATA_POOL} > /dev/null 2>&1; then
          ceph ${CEPH_OPTS} osd pool create ${CEPHFS_METADATA_POOL} ${CEPHFS_METADATA_POOL_PG}
       fi

       ceph ${CEPH_OPTS} fs new ${CEPHFS_NAME} ${CEPHFS_METADATA_POOL} ${CEPHFS_DATA_POOL}
    fi
  fi

  log "SUCCESS"
  # NOTE: prefixing this with exec causes it to die (commit suicide)
  /usr/bin/ceph-mds ${CEPH_OPTS} -d -i ${MDS_NAME} --setuser ceph --setgroup ceph
}
