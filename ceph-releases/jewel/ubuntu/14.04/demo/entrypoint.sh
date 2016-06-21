#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${RGW_NAME:=$(hostname -s)}
: ${MON_NAME:=$(hostname -s)}
: ${RGW_CIVETWEB_PORT:=80}
: ${NETWORK_AUTO_DETECT:=0}

CEPH_OPTS="--cluster ${CLUSTER}"


# FUNCTIONS
function create_socket_dir {
  mkdir -p /var/run/ceph
  chown ceph. /var/run/ceph
}

#######
# MON #
#######

function bootstrap_mon {
  if [[ ! -n "$CEPH_PUBLIC_NETWORK" && ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
    echo "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
    exit 1
  fi

  if [[ ! -n "$MON_IP" && ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
    echo "ERROR- MON_IP must be defined as the IP address of the monitor"
    exit 1
  fi

  if [ ${NETWORK_AUTO_DETECT} -ne 0 ]; then
    if command -v ip; then
      if [ ${NETWORK_AUTO_DETECT} -eq 1 ]; then
        MON_IP=$(ip -6 -o a | grep scope.global | awk '/eth|ens|eno|enp/ { sub ("/..", "", $4); print $4 }' | head -n1)
        if [ -z "$MON_IP" ]; then
          MON_IP=$(ip -4 -o a | awk '/eth|ens|eno|enp/ { sub ("/..", "", $4); print $4 }')
          CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
        fi
      elif [ ${NETWORK_AUTO_DETECT} -eq 4 ]; then
        MON_IP=$(ip -4 -o a | awk '/eth|ens|eno|enp/ { sub ("/..", "", $4); print $4 }')
        CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
      elif [ ${NETWORK_AUTO_DETECT} -eq 6 ]; then
        MON_IP=$(ip -6 -o a | grep scope.global | awk '/eth|ens|eno|enp/ { sub ("/..", "", $4); print $4 }' | head -n1)
        CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
      fi
    # best effort, only works with ipv4
    else
      MON_IP=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' /proc/net/fib_trie | grep -vEw "^127|255$|0$" | head -1)
      CEPH_PUBLIC_NETWORK=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' /proc/net/fib_trie | grep -vE "^127|^0" | head -1)
    fi
  fi

  if [[ -z "$MON_IP" || -z "$CEPH_PUBLIC_NETWORK" ]]; then
    echo "ERROR- it looks like we have not been able to discover the network settings"
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
public network = ${CEPH_PUBLIC_NETWORK}
cluster network = ${CEPH_PUBLIC_NETWORK}
ENDHERE

		# For ext4
		if [ "$(findmnt -n -o FSTYPE -T /var/lib/ceph)" = "ext4" ]; then
			cat <<ENDHERE >> /etc/ceph/${CLUSTER}.conf
osd max object name len = 256
osd max object namespace len = 64
ENDHERE
		fi

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

    # Make user 'ceph' the owner of all the tree
    chown ceph. /var/lib/ceph/bootstrap-{osd,mds,rgw}

    # Prepare the monitor daemon's directory with the map and keyring
    chown -R ceph. /var/lib/ceph/mon
    ceph-mon ${CEPH_OPTS} --mkfs -i ${MON_NAME} --monmap /etc/ceph/${CLUSTER}.monmap --keyring /tmp/${CLUSTER}.mon.keyring
    ceph-mon ${CEPH_OPTS} --setuser ceph --setgroup ceph --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap --keyring /tmp/${CLUSTER}.mon.keyring --mon-data /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  fi

  # start MON
  create_socket_dir
  chown -R ceph. /var/lib/ceph/mon
  ceph-mon ${CEPH_OPTS} -i ${MON_NAME} --public-addr "${MON_IP}:6789" --setuser ceph --setgroup ceph

  # change replica size
  ceph ${CEPH_OPTS} osd pool set rbd size 1
}


#######
# OSD #
#######

function bootstrap_osd {
  if [ ! -e /var/lib/ceph/osd/${CLUSTER}-0/keyring ]; then
    # bootstrap OSD
    mkdir -p /var/lib/ceph/osd/${CLUSTER}-0
    ceph ${CEPH_OPTS} osd create
    chown -R ceph. /var/lib/ceph/osd/${CLUSTER}-0
    ceph-osd ${CEPH_OPTS} -i 0 --mkfs --setuser ceph --setgroup ceph
    ceph ${CEPH_OPTS} auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-0/keyring
    ceph ${CEPH_OPTS} osd crush add 0 1 root=default host=$(hostname -s)
  fi

  # start OSD
  chown -R ceph. /var/lib/ceph/osd/${CLUSTER}-0
  ceph-osd ${CEPH_OPTS} -i 0 --setuser ceph --setgroup ceph
}


#######
# MDS #
#######

function bootstrap_mds {
  if [ ! -e /var/lib/ceph/mds/${CLUSTER}-0/keyring ]; then
    # create ceph filesystem
    ceph ${CEPH_OPTS} osd pool create cephfs_data 8
    ceph ${CEPH_OPTS} osd pool create cephfs_metadata 8
    ceph ${CEPH_OPTS} fs new cephfs cephfs_metadata cephfs_data

    # bootstrap MDS
    mkdir -p /var/lib/ceph/mds/${CLUSTER}-0
    ceph ${CEPH_OPTS} auth get-or-create mds.0 mds 'allow' osd 'allow *' mon 'allow profile mds' > /var/lib/ceph/mds/${CLUSTER}-0/keyring
    chown -R ceph. /var/lib/ceph/mds/${CLUSTER}-0
  fi

  # start MDS
  ceph-mds ${CEPH_OPTS} -i 0 --setuser ceph --setgroup ceph
}

#######
# RGW #
#######

function bootstrap_rgw {
  if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then
    # bootstrap RGW
    mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}
    ceph ${CEPH_OPTS} auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
    chown -R ceph. /var/lib/ceph/radosgw/${RGW_NAME}
  fi

  # start RGW
  radosgw ${CEPH_OPTS} -c /etc/ceph/${CLUSTER}.conf -n client.radosgw.gateway -k /var/lib/ceph/radosgw/${RGW_NAME}/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=${RGW_CIVETWEB_PORT}" --setuser ceph --setgroup ceph
}

#######
# API #
#######

function bootstrap_rest_api {
  # start ceph-rest-api
  ceph-rest-api ${CEPH_OPTS} -n client.admin &
}

#########
# WATCH #
#########

mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}
bootstrap_mon
bootstrap_osd
bootstrap_mds
bootstrap_rgw
bootstrap_rest_api
exec ceph ${CEPH_OPTS} -w
