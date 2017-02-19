# Ceph Demo AIO
#

FROM centos:7
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION kraken

# Install prerequisites
RUN yum install -y unzip

# Install Ceph
RUN rpm --import 'https://download.ceph.com/keys/release.asc'
RUN rpm -Uvh http://download.ceph.com/rpm-${CEPH_VERSION}/el7/noarch/ceph-release-1-1.el7.noarch.rpm
RUN yum install -y epel-release && yum clean all
RUN yum install -y ceph ceph-radosgw rbd-mirror sharutils python34 nfs-ganesha-rgw nfs-ganesha-vfs nfs-ganesha-ceph s3cmd && yum clean all

# Add entrypoint
ADD entrypoint.sh /entrypoint.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Expose the Ceph ports
EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
