#!/bin/sh

checksum()
{
	md5sum $1 | awk '{print $1}'
}

if [ ! -e /opt/bin/ceph ] || [ "$(checksum /opt/bin/ceph)" != "$(checksum /ceph)" ]; then
	echo "Installing ceph to /opt/bin"
	cp -pf /ceph /opt/bin
fi
