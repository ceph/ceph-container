# CEPH BASE IMAGE
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.x

FROM fedora:23
MAINTAINER Daniel Gryniewicz "dang@redhat.com"

ENV ETCDCTL_VERSION v2.2.4
ENV ETCDCTL_ARCH linux-amd64
ENV CEPH_VERSION hammer
ENV KVIATOR_VERSION 0.0.7
ENV CONFD_VERSION 0.10.0

# Download kviator
ADD https://github.com/AcalephStorage/kviator/releases/download/v${KVIATOR_VERSION}/kviator-${KVIATOR_VERSION}-linux-amd64.zip /kviator.zip

# Download confd
ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64 /usr/local/bin/confd

# install prerequisites
RUN dnf install -y unzip tar psmisc redhat-lsb-core && \
\
# Install Ceph (Fedora has up-to-date ceph)
    dnf install -y ceph && \
\
# Install etcdctl
    curl -L -q "https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz" | tar xfz - -C/tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl && \
    mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl && \
\
# Install kviator
    cd /usr/local/bin && unzip /kviator.zip && chmod +x /usr/local/bin/kviator && rm /kviator.zip && \
\
# Install confd
    chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
