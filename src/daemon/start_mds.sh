#!/bin/bash
set -e

function start_mds {
  get_config
  check_config

  # The first check is a backward compatible check, the commit after f34ceff02553398814793cc939213222d95a475d
  # broke the MDS_NAME variable for existing users. MDS_NAME was actually wrong from the beginning and the prefix
  # should have never existed. This check verifies if a legacy MDS runs already, if so we don't do anything.
  if [ ! -e /var/lib/ceph/mds/"${CLUSTER}"-mds-"${MDS_NAME}"/keyring ]; then
    if [ ! -e "$MDS_KEYRING" ]; then
      if [ -e "$ADMIN_KEYRING" ]; then
        keyring_opt=(--name client.admin --keyring "$ADMIN_KEYRING")
      elif [ -e "$MDS_BOOTSTRAP_KEYRING" ]; then
        keyring_opt=(--name client.bootstrap-mds --keyring "$MDS_BOOTSTRAP_KEYRING")
      else
        log "ERROR- Failed to bootstrap MDS: could not find admin or bootstrap-mds keyring.  You can extract it from your current monitor by running 'ceph auth get client.bootstrap-mds -o $MDS_BOOTSTRAP_KEYRING"
        exit 1
      fi

      timeout 10 ceph "${CLI_OPTS[@]}" "${keyring_opt[@]}" health || exit 1

      # Generate the MDS key
      ceph "${CLI_OPTS[@]}" "${keyring_opt[@]}" auth get-or-create mds."$MDS_NAME" osd 'allow rwx' mds 'allow' mon 'allow profile mds' -o "$MDS_KEYRING"
      chown "${CHOWN_OPT[@]}" ceph. "$MDS_KEYRING"
      chmod 600 "$MDS_KEYRING"

    fi
  fi

  # NOTE (leseb): having the admin keyring is really a security issue
  # If we need to bootstrap a MDS we should probably create the following on the monitors
  # I understand that this handy to do this here
  # but having the admin key inside every container is a concern

  # Create the Ceph filesystem, if necessary
  if [ "$CEPHFS_CREATE" -eq 1 ]; then

    get_admin_key
    check_admin_key

    if [[ "$(ceph "${CLI_OPTS[@]}" fs ls | grep -c name:."${CEPHFS_NAME}",)" -eq 0 ]]; then
      # Make sure the specified data pool exists
      if ! timeout 3 ceph "${CLI_OPTS[@]}" osd pool stats "${CEPHFS_DATA_POOL}" > /dev/null 2>&1; then
       ceph "${CLI_OPTS[@]}" osd pool create "${CEPHFS_DATA_POOL}" "${CEPHFS_DATA_POOL_PG}"
      fi

      # Make sure the specified metadata pool exists
      if ! timeout 3 ceph "${CLI_OPTS[@]}" osd pool stats "${CEPHFS_METADATA_POOL}" > /dev/null 2>&1; then
         ceph "${CLI_OPTS[@]}" osd pool create "${CEPHFS_METADATA_POOL}" "${CEPHFS_METADATA_POOL_PG}"
      fi

      ceph "${CLI_OPTS[@]}" fs new "${CEPHFS_NAME}" "${CEPHFS_METADATA_POOL}" "${CEPHFS_DATA_POOL}"
    fi
  fi

  log "SUCCESS"
  # NOTE: prefixing this with exec causes it to die (commit suicide)
  /usr/bin/ceph-mds "${DAEMON_OPTS[@]}" -i "${MDS_NAME}"
}
