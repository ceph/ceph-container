# CEPH BASE IMAGE
# CEPH VERSION: Hammer
# CEPH VERSION DETAIL: 0.94.x

FROM centos:7
MAINTAINER Sébastien Han "seb@redhat.com"

ENV ETCDCTL_VERSION v2.2.0
ENV ETCDCTL_ARCH linux-amd64
ENV CEPH_VERSION hammer

# Install prerequisites
RUN yum install -y unzip

# Install Runit
RUN curl -s https://packagecloud.io/install/repositories/imeyer/runit/script.rpm.sh | bash
RUN yum install -y runit-2.1.1-7.el7.centos.x86_64

# Install Ceph
RUN rpm --import 'https://download.ceph.com/keys/release.asc'
RUN rpm -Uvh https://download.ceph.com/rpm-${CEPH_VERSION}/rhel7/noarch/ceph-release-1-1.el7.noarch.rpm
RUN yum install -y epel-release && yum clean all
RUN yum install -y ceph ceph-radosgw sharutils && yum clean all
ENV KVIATOR_VERSION 0.0.7
ENV CONFD_VERSION 0.10.0

# Install etcdctl
RUN curl -L --remote-name https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz && tar xfz etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz -C /tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl
RUN mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl

#install kviator
ADD https://github.com/AcalephStorage/kviator/releases/download/v${KVIATOR_VERSION}/kviator-${KVIATOR_VERSION}-linux-amd64.zip /tmp/kviator.zip
RUN cd /usr/local/bin && unzip /tmp/kviator.zip && chmod +x /usr/local/bin/kviator && rm /tmp/kviator.zip

# Install confd
ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64 /usr/local/bin/confd
RUN chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

