# CEPH BASE IMAGE
# CEPH VERSION: Firefly
# CEPH VERSION DETAIL: 0.80.8

FROM ubuntu:14.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION firefly
ENV ETCDCTL_VERSION v2.0.4
ENV ETCDCTL_ARCH linux-amd64

# Install prerequisites
RUN apt-get update
RUN apt-get install -y wget

# Install Ceph
RUN wget -q -O- 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc' | apt-key add -
RUN echo deb http://ceph.com/debian-$CEPH_VERSION/ trusty main | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list
RUN apt-get update
RUN apt-get install -y --force-yes ceph

# Install etcdctl
RUN wget -q -O- "https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz" |tar xfz - -C/tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl
RUN mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

