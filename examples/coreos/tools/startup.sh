#!/bin/sh

checksum()
{
	md5sum $1 | awk '{print $1}'
}

for UTIL in ceph ceph-disk rados rbd; do

    if [ ! -e /opt/bin/$UTIL ] || [ "$(checksum /opt/bin/$UTIL)" != "$(checksum /$UTIL)" ]; then
    	echo "Installing $UTIL to /opt/bin"
    	cp -pf /$UTIL /opt/bin
    fi

done
