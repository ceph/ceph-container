# CEPH BASE IMAGE
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.x

FROM fedora:24
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CONFD_VERSION 0.10.0

# Download confd
ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64 /usr/local/bin/confd

# Download forego
ADD https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-amd64.tgz /forego.tgz

ARG PACKAGES="unzip ceph-mon ceph-osd ceph-mds ceph-base ceph-common ceph-radosgw rbd-mirror device-mapper sharutils etcd kubernetes-client nfs-ganesha-vfs wget systemd-udev nfs-ganesha-ceph"

# install prerequisites
RUN dnf install -y $PACKAGES && \
    rpm -q $PACKAGES && \
    dnf clean all && \
# Install confd
    chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates && \
\
# Install forego
    cd /usr/local/bin && tar xfz /forego.tgz && chmod +x /usr/local/bin/forego && rm /forego.tgz

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
