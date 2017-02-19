# Ceph Demo AIO
#

FROM ubuntu:16.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION kraken

# Install Ceph and prerequisites
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wget unzip uuid-runtime python-setuptools udev sharutils python3 s3cmd && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3FE869A9 && \
    echo "deb http://ppa.launchpad.net/gluster/nfs-ganesha/ubuntu xenial main" | tee /etc/apt/sources.list.d/nfs-ganesha.list && \
    echo "deb http://ppa.launchpad.net/gluster/libntirpc/ubuntu xenial main" | tee /etc/apt/sources.list.d/libntirpc.list && \
    wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - && \
    echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ xenial main" | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
    apt-get update && apt-get install -y --force-yes ceph radosgw rbd-mirror nfs-ganesha nfs-ganesha-fsal && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add entrypoint
ADD entrypoint.sh /entrypoint.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Expose the Ceph ports
EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
