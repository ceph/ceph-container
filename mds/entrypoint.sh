#!/bin/bash
set -e

# Expected environment variables:
#   MDS_NAME - (name of metadata server)
# Optional environment variables:
#   CEPHFS_NAME (defaults to 'cephfs')
#   CEPHFS_DATA_POOL (defaults to ${CEPHFS_NAME}_data)
#   CEPHFS_DATA_POOL_PG (defaults to 8)
#   CEPHFS_METADATA_POOL (defaults to ${CEPHFS_NAME}_metadata)
#   CEPHFS_METADATA_POOL_PG (defaults to 8)
# Usage:
#   docker run -e MDS_NAME=mymds ceph/mds

: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}

if [ ! -n "$MDS_NAME" ]; then
   echo "ERROR- MDS_NAME must be defined as the name of the metadata server"
   exit 1
fi

if [ ! -e /etc/ceph/ceph.conf ]; then
   echo "ERROR- /etc/ceph/ceph.conf must exist; get it from another ceph node"
   exit 2
fi

# Check to see if we are a new MDS
if [ ! -e /var/lib/ceph/mds/ceph-$MDS_NAME/keyring ]; then

   mkdir -p /var/lib/ceph/mds/ceph-${MDS_NAME}

   # See if we need to generate a key for the MDS
   if [ -e /etc/ceph/ceph.mds.keyring ]; then
      cp /etc/ceph/ceph.mds.keyring /var/lib/ceph/mds/ceph-${MDS_NAME}/keyring
   else
      # See if we have an admin keyring with which to generate the MDS key
      if [ ! -e /etc/ceph/ceph.client.admin.keyring ]; then
         echo "ERROR- You must have one of /etc/ceph/ceph.mds.keyring or /etc/ceph/ceph/client.admin.keyring in order to build a new metadata server"
         exit 2
      fi

      # Generate the new MDS key
      ceph auth get-or-create mds.$MDS_NAME mds 'allow' osd 'allow *' mon 'allow profile mds' > /var/lib/ceph/mds/ceph-${MDS_NAME}/keyring
   fi

fi

# Create the Ceph filesystem, if necessary
if [ $CEPHFS_CREATE -gt 0 ]; then
   FS_EXISTS=$(ceph fs ls | grep -c name:.${CEPHFS_NAME},)
   if [ $FS_EXISTS -eq 0 ]; then
      # Make sure the specified data pool exists
      ceph osd pool stats ${CEPHFS_DATA_POOL} >/dev/null
      if [ $? -ne 0 ]; then
         ceph osd pool create ${CEPHFS_DATA_POOL} ${CEPHFS_DATA_POOL_PG}
      fi

      # Make sure the specified metadata pool exists
      ceph osd pool stats ${CEPHFS_METADATA_POOL} >/dev/null
      if [ $? -ne 0 ]; then
         ceph osd pool create ${CEPHFS_METADATA_POOL} ${CEPHFS_METADATA_POOL_PG}
      fi

      ceph fs new ${CEPHFS_NAME} ${CEPHFS_METADATA_POOL} ${CEPHFS_DATA_POOL}
   fi
fi

# NOTE: prefixing this with exec causes it to die (commit suicide)
/usr/bin/ceph-mds -d -i ${MDS_NAME}
