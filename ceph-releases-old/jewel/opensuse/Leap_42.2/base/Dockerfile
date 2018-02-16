# CEPH BASE IMAGE on OpenSUSE Leap 42.2
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.4

FROM opensuse:42.2
MAINTAINER Ricardo Dias "rdias@suse.com"

# Install Ceph
RUN zypper -n ref && \
    zypper -n install net-tools "ceph<11" "ceph-radosgw<11" "rbd-mirror<11" && \
    zypper clean -a

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
