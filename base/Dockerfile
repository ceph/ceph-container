# CEPH BASE IMAGE
# CEPH VERSION: Hammer
# CEPH VERSION DETAIL: 0.94.x

FROM centos
MAINTAINER Sébastien Han "seb@redhat.com"

ENV ETCDCTL_VERSION v2.0.10
ENV ETCDCTL_ARCH linux-amd64
ENV CEPH_VERSION hammer

# Install Ceph
RUN rpm --import 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc'
RUN rpm -Uvh http://ceph.com/rpm-${CEPH_VERSION}/rhel7/noarch/ceph-release-1-1.el7.noarch.rpm
RUN yum install -y epel-release && yum clean all
RUN yum install -y ceph ceph-radosgw && yum clean all

# Install etcdctl
RUN curl -L --remote-name https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz && tar xfz etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz -C /tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl
RUN mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

