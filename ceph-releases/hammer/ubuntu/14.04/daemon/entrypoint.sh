#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}
: ${CEPH_DAEMON:=${1}} # default daemon to first argument
: ${CEPH_GET_ADMIN_KEY:=0}
: ${HOSTNAME:=$(hostname -s)}
: ${MON_NAME:=${HOSTNAME}}
: ${MON_IP_AUTO_DETECT:=0}
: ${MDS_NAME:=mds-${HOSTNAME}}
: ${OSD_FORCE_ZAP:=0}
: ${OSD_JOURNAL_SIZE:=100}
: ${CRUSH_LOCATION:=root=default host=${HOSTNAME}}
: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}
: ${RGW_NAME:=${HOSTNAME}}
: ${RGW_CIVETWEB_PORT:=80}
: ${RGW_REMOTE_CGI:=0}
: ${RGW_REMOTE_CGI_PORT:=9000}
: ${RGW_REMOTE_CGI_HOST:=0.0.0.0}
: ${RESTAPI_IP:=0.0.0.0}
: ${RESTAPI_PORT:=5000}
: ${RESTAPI_BASE_URL:=/api/v0.1}
: ${RESTAPI_LOG_LEVEL:=warning}
: ${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}
: ${KV_TYPE:=none} # valid options: consul, etcd or none
: ${KV_IP:=127.0.0.1}
: ${KV_PORT:=4001} # PORT 8500 for Consul

CEPH_OPTS="--cluster ${CLUSTER}"

# ceph config file exists or die
function check_config {
if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
  echo "ERROR- /etc/ceph/${CLUSTER}.conf must exist; get it from your existing mon"
  exit 1
fi
}

# ceph admin key exists or die
function check_admin_key {
if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
    echo "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
    exit 1
fi
}

###########################
# Configuration generator #
###########################

# Load in the bootstrapping routines
# based on the data store
case "$KV_TYPE" in
   etcd|consul)
      source /config.kv.sh
      ;;
   *)
      source /config.static.sh
      ;;
esac


#######
# MON #
#######

function start_mon {
  if [ ! -n "$CEPH_PUBLIC_NETWORK" ]; then
    echo "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
    exit 1
  fi

  if [ ${MON_IP_AUTO_DETECT} -eq 1 ]; then
    MON_IP=$(ip -6 -o a | grep scope.global | awk '/eth/ { sub ("/..", "", $4); print $4 }' | head -n1)
    if [ -z "$MON_IP" ]; then
      MON_IP=$(ip -4 -o a | awk '/eth/ { sub ("/..", "", $4); print $4 }')
    fi
  elif [ ${MON_IP_AUTO_DETECT} -eq 4 ]; then
    MON_IP=$(ip -4 -o a | awk '/eth/ { sub ("/..", "", $4); print $4 }')
  elif [ ${MON_IP_AUTO_DETECT} -eq 6 ]; then
    MON_IP=$(ip -6 -o a | grep scope.global | awk '/eth/ { sub ("/..", "", $4); print $4 }' | head -n1)
  fi

  if [ ! -n "$MON_IP" ]; then
    echo "ERROR- MON_IP must be defined as the IP address of the monitor"
    exit 1
  fi

  # get_mon_config is also responsible for bootstrapping the
  # cluster, if necessary
  get_mon_config

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}/keyring ]; then

    if [ ! -e /etc/ceph/${CLUSTER}.mon.keyring ]; then
      echo "ERROR- /etc/ceph/${CLUSTER}.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o /etc/ceph/${CLUSTER}.mon.keyring' or use a KV Store"
      exit 1
    fi

    if [ ! -e /etc/ceph/monmap ]; then
      echo "ERROR- /etc/ceph/monmap must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o /etc/ceph/monmap' or use a KV Store"
      exit 1
    fi

    # Testing if it's not the first monitor, if one key doesn't exist we assume none of them exist
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --create-keyring --import-keyring /etc/ceph/${CLUSTER}.client.admin.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /etc/ceph/${CLUSTER}.mon.keyring

    # Make the monitor directory
    mkdir -p /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap --keyring /tmp/${CLUSTER}.mon.keyring

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  fi

  # start MON
  exec /usr/bin/ceph-mon ${CEPH_OPTS} -d -i ${MON_NAME} --public-addr "${MON_IP}:6789"
}


################
# OSD (common) #
################

function start_osd {
   get_config
   check_config

   if [ ${CEPH_GET_ADMIN_KEY} -eq "1" ]; then
     get_admin_key
     check_admin_key
   fi

   case "$OSD_TYPE" in
      directory)
         osd_directory
         ;;
      disk)
         osd_disk
         ;;
      activate)
         osd_activate
         ;;
      *)
         if [[ ! -d /var/lib/ceph/osd || -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
            echo "No bootstrapped OSDs found; trying ceph-disk"
            osd_disk
         else
            if [ -z "${OSD_DEVICE}" ]; then
                echo "Bootstrapped OSD(s) found; using OSD directory"
                osd_directory
            else
                echo "Bootstrapped OSD(s) found; using ${OSD_DEVICE}"
                osd_activate
            fi
         fi
         ;;
   esac
}


#################
# OSD_DIRECTORY #
#################

function osd_directory {
  if [[ ! -d /var/lib/ceph/osd || -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    echo "ERROR- could not find any OSD, did you bind mount the OSD data directory?"
    echo "ERROR- use -v <host_osd_data_dir>:<container_osd_data_dir>"
    exit 1
  fi

  for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }'); do
    if [ -n "${JOURNAL_DIR}" ]; then
       OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
    else
       if [ -n "${JOURNAL}" ]; then
          OSD_J=${JOURNAL}
       else
          OSD_J=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/journal
       fi
    fi

    # Check to see if our OSD has been initialized
    if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
      # Create OSD key and file structure
      ceph-osd ${CEPH_OPTS} -i $OSD_ID --mkfs --mkkey --mkjournal --osd-journal ${OSD_J}

      if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
        echo "ERROR- /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring'"
        exit 1
      fi

      timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1

      # Add the OSD key
      ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring auth add osd.${OSD_ID} -i /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd 'allow *' mon 'allow profile osd'

      # Add the OSD to the CRUSH map
      if [ ! -n "${HOSTNAME}" ]; then
        echo "HOSTNAME not set; cannot add OSD to CRUSH map"
        exit 1
      fi
      OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}
    fi

    mkdir -p /etc/service/${CLUSTER}-${OSD_ID}
    cat >/etc/service/${CLUSTER}-${OSD_ID}/run <<EOF
#!/bin/bash
echo "store-daemon: starting daemon on ${HOSTNAME}..."
exec ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --osd-journal ${OSD_J} -k /var/lib/ceph/osd/ceph-${OSD_ID}/keyring
EOF
    chmod +x /etc/service/${CLUSTER}-${OSD_ID}/run
  done

exec /sbin/my_init
}

#################
# OSD_CEPH_DISK #
#################

function osd_disk {
  if [[ -z "${OSD_DEVICE}" ]];then
    echo "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
    echo "ERROR- /var/lib/ceph/bootstrap-ods/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-ods -o /var/lib/ceph/bootstrap-ods/${CLUSTER}.keyring'"
    exit 1
  fi

  timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1

  mkdir -p /var/lib/ceph/osd

  # TODO:
  # -  add device format check (make sure only one device is passed

  if [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -ne "1" ]]; then
    echo "ERROR- It looks like this device is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
    exit 1
  elif [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -eq "1" ]]; then
    ceph-disk -v zap ${OSD_DEVICE}
  fi

  if [[ ! -z "${OSD_JOURNAL}" ]]; then
    ceph-disk -v prepare ${OSD_DEVICE} ${OSD_JOURNAL}
  else
    ceph-disk -v prepare ${OSD_DEVICE}
  fi

  ceph-disk -v activate ${OSD_DEVICE}1
  OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID}
}


##########################
# OSD_CEPH_DISK_ACTIVATE #
##########################

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    echo "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  mkdir -p /var/lib/ceph/osd
  ceph-disk -v activate ${OSD_DEVICE}1
  OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID}
}

#######
# MDS #
#######

function start_mds {
  get_config
  check_config

  # Check to see if we are a new MDS
  if [ ! -e /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring ]; then

     mkdir -p /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}

    if [ -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
       KEYRING_OPT="--name client.admin --keyring /etc/ceph/${CLUSTER}.client.admin.keyring"
    elif [ -e /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring ]; then
       KEYRING_OPT="--name client.bootstrap-mds --keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring"
    else
      echo "ERROR- Failed to bootstrap MDS: could not find admin or bootstrap-mds keyring.  You can extract it from your current monitor by running 'ceph auth get client.bootstrap-mds -o /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring'"
      exit 1
    fi

    timeout 10 ceph ${CEPH_OPTS} $KEYRING_OPT health || exit 1

    # Generate the MDS key
    ceph ${CEPH_OPTS} $KEYRING_OPT auth get-or-create mds.$MDS_NAME osd 'allow rwx' mds 'allow' mon 'allow profile mds' -o /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring

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

  # NOTE: prefixing this with exec causes it to die (commit suicide)
  /usr/bin/ceph-mds ${CEPH_OPTS} -d -i ${MDS_NAME}
}


#######
# RGW #
#######

function start_rgw {
  get_config
  check_config

  if [ ${CEPH_GET_ADMIN_KEY} -eq "1" ]; then
    get_admin_key
    check_admin_key
  fi

  # Check to see if our RGW has been initialized
  if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then

    mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}

    if [ ! -e /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring ]; then
      echo "ERROR- /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-rgw -o /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring'"
      exit 1
    fi

    timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring health || exit 1

    # Generate the RGW key
    ceph ${CEPH_OPTS} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring auth get-or-create client.rgw.${RGW_NAME} osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
  fi

  if [ "$RGW_REMOTE_CGI" -eq 1 ]; then
    /usr/bin/radosgw -d ${CEPH_OPTS} -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="fastcgi socket_port=$RGW_REMOTE_CGI_PORT socket_host=$RGW_REMOTE_CGI_HOST"
  else
    /usr/bin/radosgw -d ${CEPH_OPTS} -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=$RGW_CIVETWEB_PORT"
  fi
}


###########
# RESTAPI #
###########

function start_restapi {
  get_config
  check_config

  # Ensure we have the admin key
  get_admin_key
  check_admin_key

  # Check to see if we need to add a [client.restapi] section; add, if necessary
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
  exec /usr/bin/ceph-rest-api ${CEPH_OPTS} -n client.admin

}

###############
# CEPH_DAEMON #
###############

# Normalize DAEMON to lowercase
CEPH_DAEMON=$(echo ${CEPH_DAEMON} |tr '[:upper:]' '[:lower:]')

# If we are given a valid first argument, set the
# CEPH_DAEMON variable from it
case "$CEPH_DAEMON" in
   mds)
      start_mds
      ;;
   mon)
      start_mon
      ;;
   osd)
      start_osd
      ;;
   osd_directory)
      OSD_TYPE="directory"
      start_osd
      ;;
   osd_ceph_disk)
      OSD_TYPE="disk"
      start_osd
      ;;
   osd_ceph_disk_activate)
      OSD_TYPE="activate"
      start_osd
      ;;
   rgw)
      start_rgw
      ;;
   restapi)
      start_restapi
      ;;
   *)
      if [ ! -n "$CEPH_DAEMON" ]; then
          echo "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name "
          echo "of the daemon you want to deploy."
          echo "Valid values for CEPH_DAEMON are MON, OSD, OSD_DIRECTORY, OSD_CEPH_DISK, OSD_CEPH_DISK_ACTIVATE, MDS, RGW, RESTAPI"
          echo "Valid values for the daemon parameter are mon, osd, osd_directory, osd_ceph_disk, osd_ceph_disk_activate, mds, rgw, restapi"
          exit 1
      fi
      ;;
esac

exit 0
