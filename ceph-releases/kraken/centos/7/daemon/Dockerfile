# CEPH BASE IMAGE
# CEPH VERSION: Kraken
# CEPH VERSION DETAIL: 11.1.X

FROM centos:7
MAINTAINER Sébastien Han "seb@redhat.com"

ENV ETCDCTL_VERSION v2.3.7
ENV ETCDCTL_ARCH linux-amd64
ENV CEPH_VERSION kraken
ENV KVIATOR_VERSION 0.0.7
ENV CONFD_VERSION 0.10.0
ENV KUBECTL_VERSION v1.4.0

# Install prerequisites
RUN yum install -y unzip

# Install Ceph
RUN rpm --import 'https://download.ceph.com/keys/release.asc'
RUN rpm -Uvh http://download.ceph.com/rpm-${CEPH_VERSION}/el7/noarch/ceph-release-1-1.el7.noarch.rpm
RUN yum install -y epel-release && yum clean all
RUN yum install -y ceph ceph-radosgw rbd-mirror sharutils python34 nfs-ganesha-rgw nfs-ganesha-vfs nfs-ganesha-ceph device-mapper && yum clean all

# Install etcdctl
RUN curl -L --remote-name https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz && tar xfz etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz -C /tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl
RUN mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl

#install kviator
ADD https://github.com/AcalephStorage/kviator/releases/download/v${KVIATOR_VERSION}/kviator-${KVIATOR_VERSION}-linux-amd64.zip /tmp/kviator.zip
RUN cd /usr/local/bin && unzip /tmp/kviator.zip && chmod +x /usr/local/bin/kviator && rm /tmp/kviator.zip

# Install confd
ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64 /usr/local/bin/confd
RUN chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates

# Install kubectl
ADD https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

ADD https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 /usr/local/bin/jq
RUN chmod +x /usr/local/bin/jq

# Download forego
ADD https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-amd64.tgz /forego.tgz
RUN cd /usr/local/bin && tar xfz /forego.tgz && chmod +x /usr/local/bin/forego && rm /forego.tgz

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* /

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
