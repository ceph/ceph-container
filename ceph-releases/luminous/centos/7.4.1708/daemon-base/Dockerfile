# CEPH DAEMON IMAGE
# CEPH VERSION: Luminous
# CEPH VERSION DETAIL: 12.x.x

FROM BASEIMAGE
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION luminous

ADD clean_container.sh /

ARG PACKAGES="unzip ceph-mon ceph-osd ceph-mds ceph-mgr ceph-base ceph-common ceph-radosgw rbd-mirror device-mapper sharutils etcd kubernetes-client e2fsprogs s3cmd wget nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw"

# Install Ceph
ADD ganesha.repo /etc/yum.repos.d/

RUN rpm --import 'https://download.ceph.com/keys/release.asc' && \
  rpm -Uvh http://download.ceph.com/rpm-${CEPH_VERSION}/el7/noarch/ceph-release-1-1.el7.noarch.rpm && \
  yum install -y epel-release && \
  yum clean all && \
  yum install -y $PACKAGES && \
  rpm -q $PACKAGES && \
  yum clean all && \
  bash /clean_container.sh && rm /clean_container.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]
