#!/bin/bash
set -e

# Expected environment variables:
#   RGW_NAME - (name of rados gateway server)
# Usage:
#   docker run -e RGW_NAME=myrgw ceph/radosgw

: ${RGW_CIVETWEB_PORT:=80}
: ${RGW_REMOTE_CGI:=0}
: ${RGW_REMOTE_CGI_PORT:=9000}
: ${RGW_REMOTE_CGI_HOST:=0.0.0.0}

if [ ! -n "$RGW_NAME" ]; then
  echo "ERROR- RGW_NAME must be defined as the name of the rados gateway server"
  exit 1
fi

if [ ! -e /etc/ceph/ceph.conf ]; then
  echo "ERROR- /etc/ceph/ceph.conf must exist; get it from another ceph node"
   exit 2
fi

# Make sure the directory exists
mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}

# Check to see if our RGW has been initialized
if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then
  # Add RGW key to the authentication database
  if [ ! -e /etc/ceph/ceph.client.admin.keyring ]; then
    echo "Cannot authenticate to Ceph monitor without /etc/ceph/ceph.client.admin.keyring.  Retrieve this from /etc/ceph on a monitor node."
    exit 1
  fi
  ceph auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
fi

if [ "$RGW_REMOTE_CGI" -eq 1 ]; then
  /usr/bin/radosgw -d -c /etc/ceph/ceph.conf -n client.radosgw.gateway -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="fastcgi socket_port=$RGW_REMOTE_CGI_PORT socket_host=$RGW_REMOTE_CGI_HOST"
else
  /usr/bin/radosgw -d -c /etc/ceph/ceph.conf -n client.radosgw.gateway -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=$RGW_CIVETWEB_PORT"
fi
