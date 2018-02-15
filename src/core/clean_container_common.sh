#!/usr/bin/env bash

# It is okay to have os- / distro-specific content for 'rm' commands here, as
# long as the '-f' option is specified. If a dir does not exist, the command
# will move on without errors.

INITIAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')

rm -rf \
    /etc/{selinux,systemd,udev} \
    /lib/{lsb,udev} \
    /tmp/* \
    /usr/lib/{locale,systemd,udev,dracut} \
    /usr/share/{doc,info,locale,man} \
    /var/cache/debconf/* \
    /var/lib/apt/lists/* \
    /var/log/* \
    /var/tmp/* && \
find  / -xdev -name "*.pyc" -exec rm -f {} \;

NEW_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}')
REMOVED_SIZE=$((INITIAL_SIZE - NEW_SIZE))
echo "$0: Removed ${REMOVED_SIZE}MB"
