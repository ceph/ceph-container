#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${RGW_NAME:=$(hostname -s)}
: ${MON_NAME:=$(hostname -s)}
: ${RGW_CIVETWEB_PORT:=80}


#######
# MON #
#######

if [ ! -n "$CEPH_NETWORK" ]; then
   echo "ERROR- CEPH_NETWORK must be defined as the name of the network for the OSDs"
   exit 1
fi

if [ ! -n "$MON_IP" ]; then
   echo "ERROR- MON_IP must be defined as the IP address of the monitor"
   exit 1
fi

# bootstrap MON
if [ ! -e /etc/ceph/ceph.conf ]; then
   fsid=$(uuidgen)
   cat <<ENDHERE >/etc/ceph/ceph.conf
[global]
fsid = $fsid
mon initial members = ${MON_NAME}
mon host = ${MON_IP}
auth cluster required = cephx
auth service required = cephx
auth client required = cephx
osd crush chooseleaf type = 0
osd journal size = 100
osd pool default pg num = 8
osd pool default pgp num = 8
osd pool default size = 1
public network = ${CEPH_NETWORK}
cluster network = ${CEPH_NETWORK}
ENDHERE

   # Generate administrator key
   ceph-authtool /etc/ceph/ceph.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'

   # Generate the mon. key
   ceph-authtool /etc/ceph/ceph.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

   # Generate initial monitor map
   monmaptool --create --add ${MON_NAME} ${MON_IP} --fsid ${fsid} /etc/ceph/monmap
fi

# If we don't have a monitor keyring, this is a new monitor
if [ ! -e /var/lib/ceph/mon/ceph-${MON_NAME}/keyring ]; then

   if [ ! -e /etc/ceph/ceph.client.admin.keyring ]; then
      echo "ERROR- /etc/ceph/ceph.client.admin.keyring must exist; get it from your existing mon"
      exit 2
   fi

   if [ ! -e /etc/ceph/ceph.mon.keyring ]; then
      echo "ERROR- /etc/ceph/ceph.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o /tmp/ceph.mon.keyring'"
      exit 3
   fi

   if [ ! -e /etc/ceph/monmap ]; then
      echo "ERROR- /etc/ceph/monmap must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o /tmp/monmap'"
      exit 4
   fi

   # Import the client.admin keyring and the monitor keyring into a new, temporary one
   ceph-authtool /tmp/ceph.mon.keyring --create-keyring --import-keyring /etc/ceph/ceph.client.admin.keyring
   ceph-authtool /tmp/ceph.mon.keyring --import-keyring /etc/ceph/ceph.mon.keyring

   # Make the monitor directory
   mkdir -p /var/lib/ceph/mon/ceph-${MON_NAME}

   # Prepare the monitor daemon's directory with the map and keyring
   ceph-mon --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap --keyring /tmp/ceph.mon.keyring

   # Clean up the temporary key
   rm /tmp/ceph.mon.keyring
fi

# start MON
ceph-mon -i ${MON_NAME} --public-addr ${MON_IP}:6789

# change replica size
ceph osd pool set rbd size 1


#######
# OSD #
#######

# bootstrap OSD
mkdir -p /var/lib/ceph/osd/ceph-0
ceph osd create
ceph-osd -i 0 --mkfs
ceph auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-0/keyring
ceph osd crush add 0 1 root=default host=$(hostname -s)
ceph-osd -i 0 -k /var/lib/ceph/osd/ceph-0/keyring

# start OSD
ceph-osd --cluster=${CLUSTER} -i 0


#######
# MDS #
#######

# create ceph filesystem
ceph osd pool create cephfs_data 8
ceph osd pool create cephfs_metadata 8
ceph fs new cephfs cephfs_metadata cephfs_data

# bootstrap MDS
mkdir -p /var/lib/ceph/mds/ceph-0
ceph auth get-or-create mds.0 mds 'allow' osd 'allow *' mon 'allow profile mds' > /var/lib/ceph/mds/${CLUSTER}-0/keyring

# start MDS
ceph-mds --cluster=${CLUSTER} -i 0


#######
# RGW #
#######

# bootstrap RGW
mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}
ceph auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring

# start RGW
radosgw -c /etc/ceph/ceph.conf -n client.radosgw.gateway -k /var/lib/ceph/radosgw/${RGW_NAME}/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=${RGW_CIVETWEB_PORT}"


#########
# WATCH #
#########

exec ceph -w
