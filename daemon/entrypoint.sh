#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}
: ${HOSTNAME:=$(hostname -s)}
: ${MON_NAME:=${HOSTNAME}}
: ${MON_IP_AUTO_DETECT:=0}
: ${MDS_NAME:=mds-$(hostname -s)}
: ${OSD_FORCE_ZAP:=0}
: ${OSD_JOURNAL_SIZE:=100}
: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}
: ${RGW_NAME:=$(hostname -s)}
: ${RGW_CIVETWEB_PORT:=80}
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

function ceph_config_check {
if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
  echo "ERROR- /etc/ceph/ceph.conf must exist; get it from your existing mon"
  exit 1
fi
}

function ceph_admin_key_check {
if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
    echo "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
    exit 1
fi
}

function create_mon_ceph_config_from_kv {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  echo "Adding Mon Host - ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/mon_host/${MON_NAME} ${MON_IP} > /dev/null 2>&1

  # Acquire lock to not run into race conditions with parallel bootstraps
  until kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} cas ${CLUSTER_PATH}/lock $MON_NAME > /dev/null 2>&1 ; do
    echo "Configuration is locked by another host. Waiting."
    sleep 1
  done

  # Update config after initial mon creation
  if kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; then
    echo "Configuration found for cluster ${CLUSTER}. Writing to disk."


    until confd -onetime -backend ${KV_TYPE} -node ${KV_IP}:${KV_PORT} -prefix="/${CLUSTER_PATH}/" ; do
      echo "Waiting for confd to update templates..."
      sleep 1
    done

    # Check/Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    echo "Adding Keyrings"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/monKeyring > /etc/ceph/ceph.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/ceph.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/bootstrapOsdKeyring > /var/lib/ceph/bootstrap-osd/ceph.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/bootstrapMdsKeyring > /var/lib/ceph/bootstrap-mds/ceph.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/bootstrapRgwKeyring > /var/lib/ceph/bootstrap-rgw/ceph.keyring


    if [ ! -f /etc/ceph/monmap ]; then
      echo "Monmap is missing. Adding initial monmap..."
      kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/monmap > /etc/ceph/monmap
      ceph mon getmap -o /etc/ceph/monmap
    fi

  else
    # Create initial Mon, keyring
    echo "No configuration found for cluster ${CLUSTER}. Generating."

    FSID=$(uuidgen)
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/common/fsid ${FSID}

    until confd -onetime -backend ${KV_TYPE} -node ${KV_IP}:${KV_PORT} -prefix="/${CLUSTER_PATH}/" ; do
      echo "Waiting for confd to write initial templates..."
      sleep 1
    done

    echo "Creating Keyrings"
    ceph-authtool /etc/ceph/ceph.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    ceph-authtool /etc/ceph/ceph.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

    # Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    # Generate the OSD bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-osd/ceph.keyring --create-keyring --gen-key -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'

    # Generate the MDS bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-mds/ceph.keyring --create-keyring --gen-key -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'

    # Generate the RGW bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-rgw/ceph.keyring --create-keyring --gen-key -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'


    echo "Creating Monmap"
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${FSID} /etc/ceph/monmap

    echo "Importing Keyrings and Monmap to KV"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/monKeyring - < /etc/ceph/ceph.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/adminKeyring - < /etc/ceph/ceph.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/bootstrapOsdKeyring - < /var/lib/ceph/bootstrap-osd/ceph.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/bootstrapMdsKeyring - < /var/lib/ceph/bootstrap-mds/ceph.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/bootstrapRgwKeyring - < /var/lib/ceph/bootstrap-rgw/ceph.keyring
    
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/monmap - < /etc/ceph/monmap

    echo "Completed initialization for ${MON_NAME}"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/monSetupComplete true > /dev/null 2>&1
  fi

  # Remove lock for other clients to install
  echo "Removing lock for ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} del ${CLUSTER_PATH}/lock > /dev/null 2>&1

}

function create_osd_ceph_config_from_kv {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  until kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; do
    echo "OSD: Waiting for monitor setup to complete..."
    sleep 5
  done

}

###############
# CEPH_DAEMON #
###############

# If we are given a valid first argument, set the
# CEPH_DAEMON variable from it
case "$1" in
   mds)
      CEPH_DAEMON=MDS
      ;;
   mon)
      CEPH_DAEMON=MON
      ;;
   osd_directory)
      CEPH_DAEMON=OSD_DIRECTORY
      ;;
   osd_ceph_disk)
      CEPH_DAEMON=OSD_CEPH_DISK
      ;;
   rgw)
      CEPH_DAEMON=RGW
      ;;
   restapi)
      CEPH_DAEMON=RESTAPI
      ;;
esac
if [ ! -n "$CEPH_DAEMON" ]; then
   echo "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name "
   echo "of the daemon you want to deploy."
   echo "Valid values for CEPH_DAEMON are MON, OSD_DIRECTORY, OSD_CEPH_DISK, MDS, RGW, RESTAPI"
   echo "Valid values for the daemon parameter are mon, osd_directory, osd_ceph_disk, mds, rgw, restapi"
   exit 1
fi


#######
# MON #
#######

if [[ "$CEPH_DAEMON" = "MON" ]]; then

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

if [[ "$KV_TYPE" = "none" ]]; then

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
public network = ${CEPH_PUBLIC_NETWORK}
cluster network = ${CEPH_CLUSTER_NETWORK}
osd journal size = ${OSD_JOURNAL_SIZE}
ENDHERE

    if [[ ! -z "$(ip -6 -o a | grep scope.global | awk '/eth/ { sub ("/..", "", $4); print $4 }' | head -n1)" ]]; then
      echo "ms_bind_ipv6 = true" >> /etc/ceph/${CLUSTER}.conf
      sed -i '/mon host/d' /etc/ceph/${CLUSTER}.conf
      echo "mon host = ${MON_IP}" >> /etc/ceph/${CLUSTER}.conf
    fi

    # Generate administrator key
    ceph-authtool /etc/ceph/ceph.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'

    # Generate the mon. key
    ceph-authtool /etc/ceph/ceph.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

    # Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    # Generate the OSD bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-osd/ceph.keyring --create-keyring --gen-key -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'

    # Generate the MDS bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-mds/ceph.keyring --create-keyring --gen-key -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'

    # Generate the RGW bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-rgw/ceph.keyring --create-keyring --gen-key -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'

    # Generate initial monitor map
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${fsid} /etc/ceph/monmap
  fi

else
  create_mon_ceph_config_from_kv
fi

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e /var/lib/ceph/mon/ceph-${MON_NAME}/keyring ]; then

    if [ ! -e /etc/ceph/ceph.mon.keyring ]; then
      echo "ERROR- /etc/ceph/ceph.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o /etc/ceph/ceph.mon.keyring' or use a KV Store"
      exit 1
    fi

    if [ ! -e /etc/ceph/monmap ]; then
      echo "ERROR- /etc/ceph/monmap must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o /etc/ceph/monmap' or use a KV Store"
      exit 1
    fi

    # Testing if it's not the first monitor, if one key doesn't exist we assume none of them exist
    ceph-authtool /tmp/ceph.mon.keyring --create-keyring --import-keyring /etc/ceph/ceph.client.admin.keyring
    ceph-authtool /tmp/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
    ceph-authtool /tmp/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-mds/ceph.keyring
    ceph-authtool /tmp/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-rgw/ceph.keyring
    ceph-authtool /tmp/ceph.mon.keyring --import-keyring /etc/ceph/ceph.mon.keyring

    # Make the monitor directory
    mkdir -p /var/lib/ceph/mon/ceph-${MON_NAME}

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap --keyring /tmp/ceph.mon.keyring

    # Clean up the temporary key
    rm /tmp/ceph.mon.keyring
  fi


  # start MON
  exec /usr/bin/ceph-mon -d -i ${MON_NAME} --public-addr "${MON_IP}:6789"
fi


################
# OSD (common) #
################

if [[ "$CEPH_DAEMON" = "OSD_DIRECTORY" ]]; then
  if [ -n "$(find /var/lib/ceph/osd -prune -empty)" ]; then
    echo "No bootstrapped OSDs found; trying ceph-disk"
    CEPH_DAEMON="OSD_CEPH_DISK"
  else
    echo "Bootstrapped OSD(s) found; using OSD directory"
    CEPH_DAEMON="OSD_DIRECTORY"
  fi
fi


#################
# OSD_DIRECTORY #
#################

if [[ "$CEPH_DAEMON" = "OSD_DIRECTORY" ]]; then

  ceph_config_check

  if [ -n "$(find /var/lib/ceph/osd -prune -empty)" ]; then
    echo "ERROR- could not find any OSD, did you bind mount the OSD data directory?"
    echo "ERROR- use -v <host_osd_data_dir>:<container_osd_data_dir>"
    exit 1
  fi

  for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }')
  do
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
      ceph-osd -i $OSD_ID --mkfs --mkjournal --osd-journal ${OSD_J}

      if [ ! -e /var/lib/ceph/bootstrap-osd/ceph.keyring ]; then
        echo "ERROR- /var/lib/ceph/bootstrap-osd/ceph.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring'"
        exit 1
      fi

      timeout 10 ceph --cluster ${CLUSTER} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring health || exit 1

      # Generate the OSD key
      ceph --cluster ${CLUSTER} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring auth get-or-create osd.${OSD_ID} osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring

      # Add the OSD to the CRUSH map
      if [ ! -n "${HOSTNAME}" ]; then
        echo "HOSTNAME not set; cannot add OSD to CRUSH map"
        exit 1
      fi
      ceph --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} root=default host=${HOSTNAME}
    fi

    mkdir -p /etc/service/ceph-${OSD_ID}
    cat >/etc/service/ceph-${OSD_ID}/run <<EOF
#!/bin/bash
echo "store-daemon: starting daemon on ${HOSTNAME}..."
exec ceph-osd -f -d -i ${OSD_ID} --osd-journal ${OSD_J} -k /var/lib/ceph/osd/ceph-${OSD_ID}/keyring
EOF
    chmod +x /etc/service/ceph-${OSD_ID}/run
  done

exec /sbin/my_init


#################
# OSD_CEPH_DISK #
#################

elif [[ "$CEPH_DAEMON" = "OSD_CEPH_DISK" ]]; then

  ceph_config_check

  if [[ -z "${OSD_DEVICE}" ]];then
    echo "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  if [ ! -e /var/lib/ceph/bootstrap-osd/ceph.keyring ]; then
    echo "ERROR- /var/lib/ceph/bootstrap-ods/ceph.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-ods -o /var/lib/ceph/bootstrap-ods/ceph.keyring'"
    exit 1
  fi

  timeout 10 ceph --cluster ${CLUSTER} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring health || exit 1

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
    ceph-disk -v prepare ${OSD_DEVICE}:${OSD_JOURNAL}
  else
    ceph-disk -v prepare ${OSD_DEVICE}
  fi

  ceph-disk -v activate ${OSD_DEVICE}1
  OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} root=default host=$(hostname)

  exec /usr/bin/ceph-osd -f -d -i ${OSD_ID}


#######
# MDS #
#######

elif [[ "$CEPH_DAEMON" = "MDS" ]]; then

  ceph_config_check

  # Check to see if we are a new MDS
  if [ ! -e /var/lib/ceph/mds/ceph-${MDS_NAME}/keyring ]; then

     mkdir -p /var/lib/ceph/mds/ceph-${MDS_NAME}

    if [ ! -e /var/lib/ceph/bootstrap-mds/ceph.keyring ]; then
      echo "ERROR- /var/lib/ceph/bootstrap-mds/ceph.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-mds -o /var/lib/ceph/bootstrap-mds/ceph.keyring'"
      exit 1
    fi

    timeout 10 ceph --cluster ${CLUSTER} --name client.bootstrap-mds --keyring /var/lib/ceph/bootstrap-mds/ceph.keyring health || exit 1

    # Generate the MDS key
    ceph --cluster ${CLUSTER} --name client.bootstrap-mds --keyring /var/lib/ceph/bootstrap-mds/ceph.keyring auth get-or-create mds.$MDS_NAME osd 'allow rwx' mds 'allow' mon 'allow profile mds' > /var/lib/ceph/mds/ceph-${MDS_NAME}/keyring

  fi

  # NOTE (leseb): having the admin keyring is really a security issue
  # If we need to bootstrap a MDS we should probably create the following on the monitors
  # I understand that this handy to do this here
  # but having the admin key inside every container is a concern

  # Create the Ceph filesystem, if necessary
  if [ $CEPHFS_CREATE -eq 1 ]; then

    ceph_admin_key_check

    if [[ "$(ceph fs ls | grep -c name:.${CEPHFS_NAME},)" -eq "0" ]]; then
       # Make sure the specified data pool exists
       if ! ceph osd pool stats ${CEPHFS_DATA_POOL} > /dev/null 2>&1; then
          ceph osd pool create ${CEPHFS_DATA_POOL} ${CEPHFS_DATA_POOL_PG}
       fi

       # Make sure the specified metadata pool exists
       if ! ceph osd pool stats ${CEPHFS_METADATA_POOL} > /dev/null 2>&1; then
          ceph osd pool create ${CEPHFS_METADATA_POOL} ${CEPHFS_METADATA_POOL_PG}
       fi

       ceph fs new ${CEPHFS_NAME} ${CEPHFS_METADATA_POOL} ${CEPHFS_DATA_POOL}
    fi
  fi

  # NOTE: prefixing this with exec causes it to die (commit suicide)
  /usr/bin/ceph-mds -d -i ${MDS_NAME}


#######
# RGW #
#######

elif [[ "$CEPH_DAEMON" = "RGW" ]]; then

  ceph_config_check

  # Check to see if our RGW has been initialized
  if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then

    mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}

    if [ ! -e /var/lib/ceph/bootstrap-rgw/ceph.keyring ]; then
      echo "ERROR- /var/lib/ceph/bootstrap-rgw/ceph.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-rgw -o /var/lib/ceph/bootstrap-rgw/ceph.keyring'"
      exit 1
    fi

    timeout 10 ceph --cluster ${CLUSTER} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/ceph.keyring health || exit 1

    # Generate the RGW key
    ceph --cluster ${CLUSTER} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/ceph.keyring auth get-or-create client.rgw.${RGW_NAME} osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
  fi

  if [ "$RGW_REMOTE_CGI" -eq 1 ]; then
    /usr/bin/radosgw -d -c /etc/ceph/ceph.conf -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="fastcgi socket_port=$RGW_REMOTE_CGI_PORT socket_host=$RGW_REMOTE_CGI_HOST"
  else
    /usr/bin/radosgw -d -c /etc/ceph/ceph.conf -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=$RGW_CIVETWEB_PORT"
  fi


###########
# RESTAPI #
###########

elif [[ "$CEPH_DAEMON" = "RESTAPI" ]]; then

  ceph_config_check
  ceph_admin_key_check

  # to avoid having a lot of [client.restapi] we check if one exists
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
  exec /usr/bin/ceph-rest-api -n client.admin

###########
# UNKNOWN #
###########

else

  echo "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name "
  echo "of the daemon you want to deploy."
  echo "Valid values for CEPH_DAEMON are MON, OSD_DIRECTORY, OSD_CEPH_DISK, MDS, RGW, RESTAPI"
  echo "Valid values for the daemon parameter are mon, osd_directory, osd_ceph_disk, mds, rgw, restapi"
  exit 1
fi
