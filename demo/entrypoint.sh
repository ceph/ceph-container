#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${RGW_NAME:=$(hostname -s)}
: ${MON_NAME:=$(hostname -s)}
: ${RGW_CIVETWEB_PORT:=80}

CEPH_OPTS="--cluster ${CLUSTER}"

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
if [ ! -e /etc/ceph/${CLUSTER}.conf ]; then
   fsid=$(uuidgen)
   cat <<ENDHERE >/etc/ceph/${CLUSTER}.conf
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
   ceph-authtool /etc/ceph/${CLUSTER}.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'

   # Generate the mon. key
   ceph-authtool /etc/ceph/${CLUSTER}.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

   # Generate initial monitor map
   monmaptool --create --add ${MON_NAME} ${MON_IP} --fsid ${fsid} /etc/ceph/${CLUSTER}.monmap
fi

# If we don't have a monitor keyring, this is a new monitor
if [ ! -e /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}/keyring ]; then

   if [ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
      echo "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
      exit 2
   fi

   if [ ! -e /etc/ceph/${CLUSTER}.mon.keyring ]; then
      echo "ERROR- /etc/ceph/${CLUSTER}.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph ${CEPH_OPTS} auth get mon. -o /tmp/${CLUSTER}.mon.keyring'"
      exit 3
   fi

   if [ ! -e /etc/ceph/${CLUSTER}.monmap ]; then
      echo "ERROR- /etc/ceph/${CLUSTER}.monmap must exist.  You can extract it from your current monitor by running 'ceph ${CEPH_OPTS} mon getmap -o /tmp/monmap'"
      exit 4
   fi

   # Import the client.admin keyring and the monitor keyring into a new, temporary one
   ceph-authtool /tmp/${CLUSTER}.mon.keyring --create-keyring --import-keyring /etc/ceph/${CLUSTER}.client.admin.keyring
   ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /etc/ceph/${CLUSTER}.mon.keyring

   # Make the monitor directory
   mkdir -p /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}

   # Prepare the monitor daemon's directory with the map and keyring
   ceph-mon ${CEPH_OPTS} --mkfs -i ${MON_NAME} --monmap /etc/ceph/${CLUSTER}.monmap --keyring /tmp/${CLUSTER}.mon.keyring

   # Clean up the temporary key
   rm /tmp/${CLUSTER}.mon.keyring
fi

# start MON
ceph-mon ${CEPH_OPTS} -i ${MON_NAME} --public-addr ${MON_IP}

# change replica size
ceph ${CEPH_OPTS} osd pool set rbd size 1


#######
# OSD #
#######

if [ ! -e /var/lib/ceph/osd/${CLUSTER}-0/keyring ]; then
  # bootstrap OSD
  mkdir -p /var/lib/ceph/osd/${CLUSTER}-0
  ceph ${CEPH_OPTS} osd create
  ceph-osd ${CEPH_OPTS} -i 0 --mkfs
  ceph ${CEPH_OPTS} auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-0/keyring
  ceph ${CEPH_OPTS} osd crush add 0 1 root=default host=$(hostname -s)
  ceph-osd ${CEPH_OPTS} -i 0 -k /var/lib/ceph/osd/${CLUSTER}-0/keyring
fi

# start OSD
ceph-osd ${CEPH_OPTS} -i 0


#######
# MDS #
#######

if [ ! -e /var/lib/ceph/mds/${CLUSTER}-0/keyring ]; then
  # create ceph filesystem
  ceph ${CEPH_OPTS} osd pool create cephfs_data 8
  ceph ${CEPH_OPTS} osd pool create cephfs_metadata 8
  ceph ${CEPH_OPTS} fs new cephfs cephfs_metadata cephfs_data

  # bootstrap MDS
  mkdir -p /var/lib/ceph/mds/${CLUSTER}-0
  ceph ${CEPH_OPTS} auth get-or-create mds.0 mds 'allow' osd 'allow *' mon 'allow profile mds' > /var/lib/ceph/mds/${CLUSTER}-0/keyring
fi

# start MDS
ceph-mds ${CEPH_OPTS} -i 0


#######
# RGW #
#######

if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then
  # bootstrap RGW
  mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}
  ceph ${CEPH_OPTS} auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
fi

# start RGW
radosgw -c /etc/ceph/${CLUSTER}.conf -n client.radosgw.gateway -k /var/lib/ceph/radosgw/${RGW_NAME}/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=${RGW_CIVETWEB_PORT}"


#######
# API #
#######

# start ceph-rest-api
ceph-rest-api ${CEPH_OPTS} -n client.admin &


#########
# WATCH #
#########

exec ceph ${CEPH_OPTS} -w
