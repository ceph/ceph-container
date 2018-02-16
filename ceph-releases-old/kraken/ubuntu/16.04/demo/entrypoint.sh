#!/bin/bash
set -e
export LC_ALL=C

# Global variables
: ${CLUSTER:=ceph}
: ${RGW_NAME:=$(hostname -s)}
: ${MON_NAME:=$(hostname -s)}
: ${MGR_NAME:=$(hostname -s)}
: ${MON_DATA_DIR:=/var/lib/ceph/mon/${CLUSTER}-${MON_NAME}}
: ${RGW_CIVETWEB_PORT:=80}
: ${NETWORK_AUTO_DETECT:=0}
: ${RESTAPI_IP:=0.0.0.0}
: ${RESTAPI_PORT:=5000}
: ${RESTAPI_BASE_URL:=/api/v0.1}
: ${RESTAPI_LOG_LEVEL:=warning}
: ${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}

# Internal variables
MDS_KEYRING=/var/lib/ceph/mds/${CLUSTER}-0/keyring
OSD_KEYRING=/var/lib/ceph/osd/${CLUSTER}-0/keyring
ADMIN_KEYRING=/etc/ceph/${CLUSTER}.client.admin.keyring
MON_KEYRING=/etc/ceph/${CLUSTER}.mon.keyring
RGW_KEYRING=/var/lib/ceph/radosgw/${RGW_NAME}/keyring
CEPH_PATH_BASE=/var/lib/ceph
MONMAP=/etc/ceph/monmap-${CLUSTER}
MGR_KEYRING=/var/lib/ceph/mgr/${CLUSTER}-${MGR_NAME}/keyring
IPV4_REGEXP='[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'
IPV4_NETWORK_REGEXP="$IPV4_REGEXP/[0-9]\{1,2\}"
CLI_OPTS="--cluster ${CLUSTER}"
DAEMON_OPTS="--cluster ${CLUSTER} --setuser ceph --setgroup ceph"

if [[ -n $DEBUG ]]; then
  set -x
fi

#############
# FUNCTIONS #
#############

# Transform any set of strings to uppercase
function to_uppercase {
  echo "${@^^}"
}

# Test if a command line tool is available
function is_available {
  command -v $@ &>/dev/null
}

function flat_to_ipv6 {
  # Get a flat input like fe800000000000000042acfffe110003 and output fe80::0042:acff:fe11:0003
  # This input usually comes from the ipv6_route or if_inet6 files from /proc

  # First, split the string in set of 4 bytes with ":" as separator
  value=$(echo "$@" | sed -e 's/.\{4\}/&:/g' -e '$s/\:$//')

  # Let's remove the useless 0000 and "::"
  value=${value//0000/:};
  while $(echo $value | grep -q ":::"); do
    value=${value//::/:};
  done
  echo $value
}

function get_ip {
  NIC=$1
  # IPv4 is the default unless we specify it
  IP_VERSION=${2:-4}
  # We should avoid reporting any IPv6 "scope local" interface that would make the ceph bind() call to fail
  if is_available ip; then
    ip -$IP_VERSION -o a s $NIC | grep "scope global" | awk '{ sub ("/..", "", $4); print $4 }' || true
  else
    case "$IP_VERSION" in
      6)
        # We don't want local scope, so let's remove field 4 if not 00
        ip=$(flat_to_ipv6 $(grep $NIC /proc/net/if_inet6 | awk '$4==00 {print $1}'))
        # IPv6 IPs should be surrounded by brackets to let ceph-monmap being happy
        echo "[$ip]"
        ;;
      *)
        grep -o "$IPV4_REGEXP" /proc/net/fib_trie | grep -vEw "^127|255$|0$" | head -1
        ;;
    esac
  fi
}

function get_network {
  NIC=$1
  # IPv4 is the default unless we specify it
  IP_VERSION=${2:-4}

  case "$IP_VERSION" in
    6)
      if is_available ip; then
        ip -$IP_VERSION route show dev $NIC | grep proto | awk '{ print $1 }' | grep -v default | grep -vi ^fe80 || true
      else
        # We don't want the link local routes
        line=$(grep $NIC /proc/1/task/1/net/ipv6_route | awk '$2==40' | grep -v ^fe80 || true)
        base=$(echo $line | awk '{ print $1 }')
        base=$(flat_to_ipv6 $base)
        mask=$(echo $line | awk '{ print $2 }')
        echo "$base/$((16#$mask))"
      fi
      ;;
    *)
      if is_available ip; then
        ip -$IP_VERSION route show dev $NIC | grep proto | awk '{ print $1 }' | grep -v default | grep "/" || true
      else
        grep -o "$IPV4_NETWORK_REGEXP" /proc/net/fib_trie | grep -vE "^127|^0" | head -1
      fi
      ;;
  esac
}

# Log arguments with timestamp
function log {
  if [ -z "$*" ]; then
    return 1
  fi

  TIMESTAMP=$(date '+%F %T')
  echo "${TIMESTAMP}  $0: $*"
  return 0
}

function create_mandatory_directories {
  # Let's create the bootstrap directories
  for directory in osd mds rgw; do
    mkdir -p /var/lib/ceph/bootstrap-$directory
  done

  # Let's create the ceph directories
  for directory in mon osd mds radosgw tmp mgr; do
    mkdir -p /var/lib/ceph/$directory
  done

  # Create socket directory
  mkdir -p /var/run/ceph

  # Adjust the owner of all those directories
  chown --verbose -R ceph. /var/run/ceph/ /var/lib/ceph/*
}


#######
# MON #
#######

function bootstrap_mon {
  if [[ ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
      if [[ -z "$CEPH_PUBLIC_NETWORK" ]]; then
        log "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
        exit 1
      fi

      if [[ -z "$MON_IP" ]]; then
        log "ERROR- MON_IP must be defined as the IP address of the monitor"
        exit 1
      fi
  else
    NIC_MORE_TRAFFIC=$(grep -vE "lo:|face|Inter" /proc/net/dev | sort -n -k 2 | tail -1 | awk '{ sub (":", "", $1); print $1 }')
    IP_VERSION=4
    if [ ${NETWORK_AUTO_DETECT} -gt 1 ]; then
      MON_IP=$(get_ip ${NIC_MORE_TRAFFIC} ${NETWORK_AUTO_DETECT})
      CEPH_PUBLIC_NETWORK=$(get_network ${NIC_MORE_TRAFFIC} ${NETWORK_AUTO_DETECT})
      IP_VERSION=${NETWORK_AUTO_DETECT}
    else # Means -eq 1
      MON_IP="[$(get_ip ${NIC_MORE_TRAFFIC} 6)]"
      CEPH_PUBLIC_NETWORK=$(get_network ${NIC_MORE_TRAFFIC} 6)
      IP_VERSION=6
      if [ -z "$MON_IP" ]; then
        MON_IP=$(get_ip ${NIC_MORE_TRAFFIC})
        CEPH_PUBLIC_NETWORK=$(get_network ${NIC_MORE_TRAFFIC})
        IP_VERSION=4
      fi
    fi
  fi

  if [[ -z "$MON_IP" || -z "$CEPH_PUBLIC_NETWORK" ]]; then
    log "ERROR- it looks like we have not been able to discover the network settings"
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
    ceph-authtool $ADMIN_KEYRING --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'

    # Generate the mon. key
    ceph-authtool $MON_KEYRING --create-keyring --gen-key -n mon. --cap mon 'allow *'

    # Generate initial monitor map
    monmaptool --create --add ${MON_NAME} ${MON_IP} --fsid ${fsid} $MONMAP
  fi

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e "$MON_DATA_DIR/keyring" ]; then

    if [ ! -e $ADMIN_KEYRING ]; then
      log "ERROR- $ADMIN_KEYRING must exist; get it from your existing mon"
      exit 2
    fi

    if [ ! -e $MON_KEYRING ]; then
      log "ERROR- $MON_KEYRING must exist. You can extract it from your current monitor by running 'ceph ${CLI_OPTS} auth get mon. -o /tmp/${CLUSTER}.mon.keyring'"
      exit 3
    fi

    if [ ! -e $MONMAP ]; then
      log "ERROR- $MONMAP must exist. You can extract it from your current monitor by running 'ceph ${CLI_OPTS} mon getmap -o /tmp/monmap-${CLUSTER}'"
      exit 4
    fi

    # Import the client.admin keyring and the monitor keyring into a new, temporary one
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --create-keyring --import-keyring $ADMIN_KEYRING
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring $MON_KEYRING

    # Make the monitor directory
    mkdir -p "$MON_DATA_DIR"

    # Prepare the monitor daemon's directory with the map and keyring
    chown --verbose -R ceph. $CEPH_PATH_BASE/mon /tmp/${CLUSTER}.mon.keyring
    ceph-mon ${CLI_OPTS} --mkfs -i ${MON_NAME} --monmap $MONMAP --keyring /tmp/${CLUSTER}.mon.keyring --mon-data "$MON_DATA_DIR"

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  fi

  # start MON
  chown --verbose -R ceph. $CEPH_PATH_BASE/mon /etc/ceph/
  ceph-mon ${DAEMON_OPTS} -i ${MON_NAME} --public-addr "${MON_IP}:6789"

  # change replica size
  ceph ${CLI_OPTS} osd pool set rbd size 1
}


#######
# OSD #
#######

function bootstrap_osd {
  if [ ! -e $CEPH_PATH_BASE/osd/${CLUSTER}-0/keyring ]; then
    # bootstrap OSD
    mkdir -p $CEPH_PATH_BASE/osd/${CLUSTER}-0
    ceph ${CLI_OPTS} osd create
    chown --verbose -R ceph. $CEPH_PATH_BASE/osd/${CLUSTER}-0
    ceph-osd ${CLI_OPTS} -i 0 --mkfs --setuser ceph --setgroup ceph
    ceph ${CLI_OPTS} auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o $OSD_KEYRING
    ceph ${CLI_OPTS} osd crush add 0 1 root=default host=localhost
  fi

  # start OSD
  chown --verbose -R ceph. $CEPH_PATH_BASE/osd/${CLUSTER}-0
  ceph-osd ${DAEMON_OPTS} -i 0
}


#######
# MDS #
#######

function bootstrap_mds {
  if [ ! -e $MDS_KEYRING ]; then
    # create ceph filesystem
    ceph ${CLI_OPTS} osd pool create cephfs_data 8
    ceph ${CLI_OPTS} osd pool create cephfs_metadata 8
    ceph ${CLI_OPTS} fs new cephfs cephfs_metadata cephfs_data

    # bootstrap MDS
    mkdir -p $CEPH_PATH_BASE/mds/${CLUSTER}-0
    ceph ${CLI_OPTS} auth get-or-create mds.0 mds 'allow' osd 'allow *' mon 'allow profile mds' -o $MDS_KEYRING
    chown --verbose -R ceph. $CEPH_PATH_BASE/mds/${CLUSTER}-0
  fi

  # start MDS
  ceph-mds ${DAEMON_OPTS} -i 0
}


#######
# RGW #
#######

function bootstrap_rgw {
  if [ ! -e $RGW_KEYRING ]; then
    # bootstrap RGW
    mkdir -p $CEPH_PATH_BASE/radosgw/${RGW_NAME}
    ceph ${CLI_OPTS} auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o $RGW_KEYRING
    chown --verbose -R ceph. $CEPH_PATH_BASE/radosgw/${RGW_NAME}

    #configure rgw dns name
    cat <<ENDHERE >>/etc/ceph/${CLUSTER}.conf
[client.radosgw.gateway]
  rgw dns name = ${RGW_NAME}
ENDHERE
  fi

  # start RGW
  radosgw ${DAEMON_OPTS} -n client.radosgw.gateway -k $RGW_KEYRING --rgw-socket-path="" --rgw-frontends="civetweb port=${RGW_CIVETWEB_PORT}"
}

function bootstrap_demo_user {
  if [ -n "$CEPH_DEMO_UID" ] && [ -n "$CEPH_DEMO_ACCESS_KEY" ] && [ -n "$CEPH_DEMO_SECRET_KEY" ]; then
    if [ -f /ceph-demo-user ]; then
      log "Demo user already exists with credentials:"
      cat /ceph-demo-user
    else
      log "Setting up a demo user..."
      radosgw-admin ${CLI_OPTS} user create --uid=$CEPH_DEMO_UID --display-name="Ceph demo user" --access-key=$CEPH_DEMO_ACCESS_KEY --secret-key=$CEPH_DEMO_SECRET_KEY
      sed -i s/AWS_ACCESS_KEY_PLACEHOLDER/$CEPH_DEMO_ACCESS_KEY/ /root/.s3cfg
      sed -i s/AWS_SECRET_KEY_PLACEHOLDER/$CEPH_DEMO_SECRET_KEY/ /root/.s3cfg
      echo "Access key: $CEPH_DEMO_ACCESS_KEY" > /ceph-demo-user
      echo "Secret key: $CEPH_DEMO_SECRET_KEY" >> /ceph-demo-user

      # Use rgw port
      sed -i "s/host_base = localhost/host_base = ${RGW_NAME}:${RGW_CIVETWEB_PORT}/" /root/.s3cfg
      sed -i "s/host_bucket = localhost/host_bucket = ${RGW_NAME}:${RGW_CIVETWEB_PORT}/" /root/.s3cfg

      if [ -n "$CEPH_DEMO_BUCKET" ]; then
        log "Creating bucket..."
        log "Transforming your bucket name to uppercase."
        log "It appears there is a bug in s3cmd 1.6.1 with lowercase bucket names."
        s3cmd mb s3://$(to_uppercase $CEPH_DEMO_BUCKET)
      fi
    fi
  fi
}


#######
# NFS #
#######

function bootstrap_nfs {
  # Init RPC
  rpcbind || return 0
  rpc.statd -L || return 0
  rpc.idmapd || return 0

  # start ganesha
  ganesha.nfsd -F ${GANESHA_OPTIONS} ${GANESHA_EPOCH}
}


#######
# API #
#######

function bootstrap_rest_api {
  if [[ ! "$(egrep "\[client.restapi\]" /etc/ceph/${CLUSTER}.conf)" ]]; then
    cat <<ENDHERE >>/etc/ceph/${CLUSTER}.conf
[client.restapi]
  public addr = ${RESTAPI_IP}:${RESTAPI_PORT}
  restapi base url = ${RESTAPI_BASE_URL}
  restapi log level = ${RESTAPI_LOG_LEVEL}
  log file = ${RESTAPI_LOG_FILE}
ENDHERE
		fi

  # start ceph-rest-api
  ceph-rest-api ${CLI_OPTS} -c /etc/ceph/${CLUSTER}.conf -n client.admin &
}


##############
# RBD MIRROR #
##############

function bootstrap_rbd_mirror {
  # start rbd-mirror
  rbd-mirror ${DAEMON_OPTS}
}


#######
# MGR #
#######

function bootstrap_mgr {
  mkdir -p $CEPH_PATH_BASE/mgr/${CLUSTER}-$MGR_NAME
  ceph ${CLI_OPTS} auth get-or-create mgr.$MGR_NAME mon 'allow *' -o $MGR_KEYRING
  chown --verbose -R ceph. $CEPH_PATH_BASE/mgr

  # start ceph-mgr
  ceph-mgr ${DAEMON_OPTS} -i $MGR_NAME
}


#########
# WATCH #
#########

create_mandatory_directories
bootstrap_mon
bootstrap_osd
bootstrap_mds
bootstrap_rgw
bootstrap_demo_user
bootstrap_rest_api
# bootstrap_nfs is temporarily disabled due to broken package dependencies with nfs-ganesha"
# For more info see: https://github.com/ceph/ceph-docker/pull/564"
#bootstrap_nfs
bootstrap_rbd_mirror
bootstrap_mgr
log "SUCCESS"
exec ceph ${CLI_OPTS} -w
