#!/bin/bash
set -e

: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}

#######
# MON #
#######

function start_mon {
  if [ ! -n "$MON_NIC" ]; then
    echo "ERROR- MON_NIC must be defined as the IP address of the monitor"
    exit 1
  fi

  if [ ! -n "$CEPH_PUBLIC_NETWORK" ]; then
    echo "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
    exit 1
  fi

      cat >/opt/ansible/ceph-ansible/inventory <<EOF
[mons]
127.0.0.1
EOF

    cat >/opt/ansible/ceph-ansible/group_vars/all <<EOF
ceph_stable: 'true'
journal_collocation: 'true'
monitor_interface: "${MON_NIC}"
journal_size: 100
public_network: "${CEPH_PUBLIC_NETWORK}"
EOF

  export ANSIBLE_CONFIG=/opt/ansible/ceph-ansible/ansible.cfg
  ansible-playbook -i /opt/ansible/ceph-ansible/inventory /opt/ansible/ceph-ansible/site.yml

  # start MON
  exec /usr/bin/ceph-mon ${CEPH_OPTS} -d -i ${MON_NAME} --public-addr "${MON_IP}:6789" --setuser ceph --setgroup ceph
}


###############
# CEPH_DAEMON #
###############

# Normalize DAEMON to lowercase
CEPH_DAEMON=$(echo ${CEPH_DAEMON} |tr '[:upper:]' '[:lower:]')

# If we are given a valid first argument, set the
# CEPH_DAEMON variable from it
case "$CEPH_DAEMON" in
   mon)
      start_mon
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
