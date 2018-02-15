#!/usr/bin/env bash

# Removing perl as we don't need it
apt-get remove -y --auto-remove perl
apt-get purge -y perl
apt-get purge -y --auto-remove perl
# Removing agressively perl-base as nothing we use call perl yet.
# perl-base is required by adduser, init-system-helpers and debconf
# At this stage of the build process, it's not a big deal breaking those tools for saving storage space
dpkg --purge --force-all perl-base libperl5.22
