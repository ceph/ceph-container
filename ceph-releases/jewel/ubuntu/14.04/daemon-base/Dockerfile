# CEPH BASE IMAGE
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.x

FROM BASEIMAGE
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION jewel


# Packages list
ARG PACKAGES="ceph radosgw rbd-mirror sharutils"

ADD clean_container.sh /

# install prerequisites
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wget unzip uuid-runtime python-setuptools udev dmsetup && \
  # Install ceph, ganesha and etcd \
  wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - && \
  echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ trusty main" | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
  apt-get update && apt-get install -y  --no-install-recommends --force-yes $PACKAGES && \
  dpkg -s $PACKAGES && \
  apt-get clean && \
  bash /clean_container.sh && rm -f /clean_container.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
