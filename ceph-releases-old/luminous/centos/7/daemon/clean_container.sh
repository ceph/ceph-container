#!/bin/bash
INITIAL_SIZE="$(du -sm / 2>/dev/null | awk '{ print $1 }')"
DEBUG=

PURGES="/tmp/* /var/tmp/* /usr/lib/{dracut,locale,systemd,udev} /usr/bin/hyperkube /usr/bin/etcd /usr/bin/systemd-analyze /etc/{udev,selinux} /usr/lib/{udev,systemd}"
PURGES="$PURGES /usr/share/hwdata/{iab.txt,oui.txt}"
# As we need to keep every PURGES as an arguement to rm, let's ignore SC2086
# shellcheck disable=SC2086
rm -rf $PURGES

PURGE_PKGS="groff-base e2fsprogs sharutils shadow-utils yum-utils python-gobject-base python-kitchen passwd bind-license policycoreutils-python epel-release"
PURGE_PKGS="$PURGE_PKGS libselinux-python libss libcgroup dbus-python yum-plugin-ovl rbd-mirror libxml2-python python-IPy checkpolicy libsemanage-python setools-libs"
PURGE_PKGS="$PURGE_PKGS systemd-sysv dbus-glib gobject-introspection audit-libs-python"

# Step 1
# Let's remove easy stuff
strip -s /usr/local/bin/{confd,forego}

# Compressing those very big binaries
# As we don't run them often, the peformance penalty isn't huge
for binary in /usr/bin/{etcdctl,kubectl} /usr/local/bin/{forego,confd}; do
  gzexe $binary && rm ${binary}~
done

rm -rf /usr/share/{doc,info,locale,man}/*

# Some logfiles are not empty, there is no need to keep them
find /var/log/ -type f -exec truncate -s 0 {} \;

STEP1_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
REMOVED_STEP1_SIZE=$((INITIAL_SIZE - STEP1_SIZE))
echo "Stripping process: Step 1 removed ${REMOVED_STEP1_SIZE}MB"

# Step 2
# Let's remove stuff than can be discussed

rm -f /usr/lib/ceph/mgr/dashboard/static/AdminLTE-*/plugins/datatables/extensions/TableTools/images/psd/* # Photoshop files inside a container ?

# Let's remove all the pre-compiled python files, if needed they will be rebuilt
find  / -xdev -name "*.pyc" -exec rm {} \; # 23MB of pyc

# ceph-dencoder is only used for debugging, compressing it saves 10MB
# If needed it will be decompressed
xz /usr/bin/ceph-dencoder

# Timezone is not configured so let's remove the zoneinfo (8MB)
rpm -e tzdata --nodeps

# Removing perl as we don't need it
# perl is required by libibverbs (Infiniband) which is required by ceph in general
# the ceph daemons are linked against the lib but we don't care about perl itself
#	perl(Getopt::Long) is needed by (installed) libibverbs-13-7.el7.x86_64
#	perl(File::Basename) is needed by (installed) libibverbs-13-7.el7.x86_64
#	perl(strict) is needed by (installed) libibverbs-13-7.el7.x86_64
#	perl(warnings) is needed by (installed) libibverbs-13-7.el7.x86_64
#	/usr/bin/perl is needed by (installed) libibverbs-13-7.el7.x86_64
# as we need to keep every rpm as an argument to rpm, let's ignore SC2046
# shellcheck disable=SC2046
rpm -e $(rpm -qa perl* | tr  "\\n" " ") --nodeps

# Removing useless packages
# As we need to keep every PURGE_PKGS as an arguement to rpm, let's ignore SC2086
# shellcheck disable=SC2086
rpm -e $PURGE_PKGS

# rebuilding the rpm database to save space (~25%)
rpmdb --rebuilddb

STEP2_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
REMOVED_STEP2_SIZE=$((STEP1_SIZE - STEP2_SIZE))
echo "Stripping process: Step 2 removed ${REMOVED_STEP2_SIZE}MB"

# Final
REMOVED_SIZE=$((INITIAL_SIZE - STEP2_SIZE))
echo "Stripping process saved ${REMOVED_SIZE}MB and dropped container size from ${INITIAL_SIZE}MB to ${STEP2_SIZE}MB"

if [ -n "$DEBUG" ]; then
  find / -xdev -type f  -exec du -c {} \; |sort -n
fi
