#!/bin/sh

checksum()
{
	md5sum $1 | awk '{print $1}'
}

if [ ! -e /opt/bin/ceph ] || [ "$(checksum /opt/bin/ceph)" != "$(checksum /ceph)" ]; then
	echo "Installing ceph to /opt/bin"
	cp -pf /ceph /opt/bin
fi

if [ ! -e /opt/bin/ceph-disk ] || [ "$(checksum /opt/bin/ceph-disk)" != "$(checksum /ceph-disk)" ]; then
	echo "Installing ceph-disk to /opt/bin"
	cp -pf /ceph-disk /opt/bin
fi

if [ ! -e /opt/bin/rados ] || [ "$(checksum /opt/bin/rados)" != "$(checksum /rados)" ]; then
	echo "Installing rados to /opt/bin"
	cp -pf /rados /opt/bin
fi

if [ ! -e /opt/bin/rbd ] || [ "$(checksum /opt/bin/rbd)" != "$(checksum /rbd)" ]; then
	echo "Installing rbd to /opt/bin"
	cp -pf /rbd /opt/bin
fi
