#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${WEIGHT:=1.0}
: ${JOURNAL:=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/journal}

# Make sure the osd id is set
if [ ! -n "$OSD_ID" ]; then
   echo "OSD_ID must be set; call 'ceph osd create' to allocate the next available osd id"
   exit 1
fi


# Check to see if our OSD has been initialized
if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
   # Create OSD key and file structure
   ceph-osd -i $OSD_ID --mkfs --mkjournal --osd-journal ${JOURNAL}

   # Add OSD key to the authentication database
   if [ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
      echo "Cannot authenticate to Ceph monitor without /etc/ceph/${CLUSTER}.client.admin.keyring.  Retrieve this from /etc/ceph on a monitor node."
      exit 1
   fi
   ceph auth get-or-create osd.${OSD_ID} osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring

   # Add the OSD to the CRUSH map
   if [ ! -n "${HOSTNAME}" ]; then
      echo "HOSTNAME not set; cannot add OSD to CRUSH map"
      exit 1
   fi
   ceph osd crush add ${OSD_ID} ${WEIGHT} root=default host=${HOSTNAME}
fi

if [ $1 == 'ceph-osd' ]; then
   exec ceph-osd -d -i ${OSD_ID} -k /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
else
   exec $@
fi
