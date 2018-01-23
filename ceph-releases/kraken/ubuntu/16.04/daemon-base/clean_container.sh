#!/bin/bash

# Step 1
# Let's remove easy stuff
rm -rf /usr/share/{doc,info,locale,man}/*
rm -f /usr/bin/{etcd-tester,etcd-dump-logs}

# Let's strip the ceph libraries
strip -s /usr/lib/ceph/erasure-code/*
strip -s /usr/lib/rados-classes/*
strip -s /usr/lib/python2.7/dist-packages/{rados,rbd,rgw}.x86_64-linux-gnu.so

rm -f /usr/lib/ceph/mgr/dashboard/static/AdminLTE-*/plugins/datatables/extensions/TableTools/images/psd/* # Photoshop files inside a container ?

# Let's remove all the pre-compiled python files, if needed they will be rebuilt
find  / -xdev -name "*.pyc" -exec rm {} \; # 23MB of pyc

# ceph-dencoder is only used for debugging, compressing it saves 10MB
# If needed it will be decompressed
gzip -9 /usr/bin/ceph-dencoder

# Some logfiles are not empty, there is no need to keep them
find /var/log/ -type f -exec truncate -s 0 {} \;

rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/lib/{dracut,locale,systemd,udev} /usr/bin/systemd-analyze /etc/{udev,selinux}
