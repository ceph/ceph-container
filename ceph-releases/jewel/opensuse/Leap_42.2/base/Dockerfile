# CEPH BASE IMAGE on OpenSUSE Leap 42.2
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.4

FROM opensuse:42.2
MAINTAINER Ricardo Dias "rdias@suse.com"

# Install Ceph
RUN zypper -n ref
RUN zypper -n install net-tools
RUN zypper -n install "ceph<11" "ceph-radosgw<11" "rbd-mirror<11"


ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
