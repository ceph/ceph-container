#!/bin/bash
set -e

function get_admin_key {
   # No-op for static
   echo "static: does not generate admin key"
}

function get_mon_config {
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
    else
      # extract fsid from ceph.conf
      fsid=`grep "fsid" /etc/ceph/${CLUSTER}.conf |awk '{print $NF}'`
  fi

  if [ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
    # Generate administrator key
    ceph-authtool /etc/ceph/${CLUSTER}.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
  fi

  if [ ! -e /etc/ceph/${CLUSTER}.mon.keyring ]; then
    # Generate the mon. key
    ceph-authtool /etc/ceph/${CLUSTER}.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'
  fi

  # Create bootstrap key directories
  mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}
  chown ceph. /var/lib/ceph/bootstrap-{osd,mds,rgw}

  if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
    # Generate the OSD bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'
  fi

  if [ ! -e /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring ]; then
    # Generate the MDS bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'
  fi

  if [ ! -e /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring ]; then
    # Generate the RGW bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'
  fi

    # Apply proper permissions to the keys
    chown ceph. /etc/ceph/${CLUSTER}.mon.keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring

  if [ ! -e /etc/ceph/monmap ]; then
    # Generate initial monitor map
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${fsid} /etc/ceph/monmap
    chown ceph. /etc/ceph/monmap
  fi

}

function get_config {
   # No-op for static
   echo "static: does not generate config"
}

