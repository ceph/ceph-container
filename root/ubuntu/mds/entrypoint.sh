#!/bin/bash
set -e

# Expected environment variables:
#   MDS_NAME - (name of metadata server)
# Usage:
#   docker run -e MDS_NAME=mymds ceph/mds

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

# NOTE: prefixing this with exec causes it to die (commit suicide)
/usr/bin/ceph-mds -d -i ${MDS_NAME}
