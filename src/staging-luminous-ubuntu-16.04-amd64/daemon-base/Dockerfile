# CEPH DAEMON BASE IMAGE

FROM ubuntu:16.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION luminous

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
ADD 'https://download.ceph.com/keys/release.asc' /tmp/release.asc

# Escape char after immediately after RUN allows comment in first line
ADD clean_container_common.sh /
RUN ( \
    apt-key add /tmp/release.asc && \
    echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ xenial main" | \
      tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yy -q --no-install-recommends \
        ca-certificates \
        ceph-common \
        ceph-mon \
        ceph-osd \
        ceph-mds \
        ceph-mgr \
        kmod \
        radosgw \
        rbd-mirror && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && \
    DEBIAN_FRONTEND=noninteractive apt-get clean ) && \
    bash -c ' \
      function ifstrip () { if compgen -g "$1"; then strip -s "$1"; fi } && \
      ifstrip /usr/lib/ceph/erasure-code/* && \
      ifstrip /usr/lib/rados-classes/* && \
      ifstrip /usr/lib/python2.7/dist-packages/{rados,rbd,rgw}.*.so' && \
    # Clean container
    bash /clean_container_common.sh && rm /clean_container_common.sh
