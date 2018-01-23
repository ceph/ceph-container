# CEPH DAEMON IMAGE
# CEPH VERSION: Luminous
# CEPH VERSION DETAIL: 12.x.x

FROM BASEIMAGE
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION luminous

ADD clean_container.sh /

# Packages list
ARG PACKAGES="ceph-mon ceph-osd ceph-mds ceph-mgr ceph-base ceph-common radosgw rbd-mirror sharutils etcd s3cmd nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw lvm2"

# install prerequisites
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wget unzip uuid-runtime python-setuptools udev dmsetup && \
  # Install ceph, ganesha and etcd \
  wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - && \
  echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ xenial main" | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
  echo "deb http://download.ceph.com/nfs-ganesha/deb-V2.5-stable/luminous/ xenial main" | tee /etc/apt/sources.list.d/nfs-ganesha.list && \
  apt-get update && apt-get install -y  --no-install-recommends --force-yes $PACKAGES && \
  dpkg -s $PACKAGES && \
  apt-get clean && \
  bash /clean_container.sh && rm -f /clean_container.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]
