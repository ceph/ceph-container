#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${WEIGHT:=1.0}
: ${JOURNAL:=/var/lib/ceph/journal}

mkdir -p ${JOURNAL}

for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }')
do
   # Check to see if our OSD has been initialized
   if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
      # Create OSD key and file structure
      ceph-osd -i $OSD_ID --mkfs --mkjournal --osd-journal ${JOURNAL}/journal.${OSD_ID}

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

   mkdir -p /etc/service/ceph-${OSD_ID}
   cat >/etc/service/ceph-${OSD_ID}/run <<EOF
#!/bin/bash
echo "store-daemon: starting daemon on ${HOSTNAME}..."
exec ceph-osd -f -d -i ${OSD_ID} --osd-journal ${JOURNAL}/journal.${OSD_ID} -k /var/lib/ceph/osd/ceph-${OSD_ID}/keyring
EOF

   chmod +x /etc/service/ceph-${OSD_ID}/run

done

read
