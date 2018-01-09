#!/bin/bash
INITIAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
DEBUG=

# Step 1
# Let's remove easy stuff
strip -s /usr/local/bin/{confd,forego,kubectl}
strip -s /usr/bin/{crushtool,monmaptool,osdmaptool}
rm -rf /usr/share/{doc,info,locale,man}/*
rm -f /usr/bin/{etcd-tester,etcd-dump-logs}

# Let's compress fat binaries but keep them executable
# As we don't run them often, the performance penalty isn't that big
for binary in /usr/local/bin/{confd,forego,kubectl} /usr/bin/etcdctl; do
  gzexe $binary && rm -f ${binary}~
done

STEP1_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
REMOVED_STEP1_SIZE=$((INITIAL_SIZE - STEP1_SIZE))
echo "Stripping process: Step 1 removed ${REMOVED_STEP1_SIZE}MB"

# Step 2
# Let's remove stuff than can be discussed

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

# Timezone is not configured so let's remove the zoneinfo (8MB)
dpkg --purge --force-all tzdata

# Removing perl as we don't need it
apt-get remove -y --auto-remove perl
apt-get purge -y perl
apt-get purge -y --auto-remove perl
# Removing agressively perl-base as nothing we use call perl yet.
# perl-base is required by adduser, init-system-helpers and debconf
# At this stage of the build process, it's not a big deal breaking those tools for saving storage space
dpkg --purge --force-all perl-base libperl5.22

# Some logfiles are not empty, there is no need to keep them
find /var/log/ -type f -exec truncate -s 0 {} \;

STEP2_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
REMOVED_STEP2_SIZE=$((STEP1_SIZE - STEP2_SIZE))
echo "Stripping process: Step 2 removed ${REMOVED_STEP2_SIZE}MB"

# Final
REMOVED_SIZE=$((INITIAL_SIZE - STEP2_SIZE))
echo "Stripping process saved ${REMOVED_SIZE}MB and dropped container size from ${INITIAL_SIZE}MB to ${STEP2_SIZE}MB"

if [ -n "$DEBUG" ]; then
  find / -xdev -type f -exec du -c {} \; |sort -n
fi
