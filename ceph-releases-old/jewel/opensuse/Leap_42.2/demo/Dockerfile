FROM ceph/base:tag-build-master-jewel-opensuse-Leap_42.2
MAINTAINER Ricardo Dias "rdias@suse.com"

ADD entrypoint.sh /entrypoint.sh
VOLUME ["/etc/ceph", "/var/lib/ceph"]

EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

ENTRYPOINT ["/entrypoint.sh"]
