# CEPH DAEMON IMAGE
# CEPH VERSION: Luminous
# CEPH VERSION DETAIL: 12.x.x

FROM opensuse:42.3
MAINTAINER Blaine Gardner "blaine.gardner@suse.com"

# OS version string for repos
ARG OS_VERSION='openSUSE_Leap_42.3'
# Prevent upgrades to a newer major release
ARG CEPH_VERSION_NUM_UPPERBOUND='13'
ENV CEPH_VERSION 'luminous'
ARG CONFD_VERSION='0.13.0'

ARG PACKAGE_MANAGER="zypper --non-interactive"
ARG ADDREPO="$PACKAGE_MANAGER addrepo"
ARG INSTALL="$PACKAGE_MANAGER install"

# Install Ceph
ARG CEPH_REPO="http://download.opensuse.org/repositories/filesystems:/ceph:/${CEPH_VERSION}/${OS_VERSION}/"
# The Cloud:Tools repo has s3cmd
ARG CLOUD_REPO="http://download.opensuse.org/repositories/Cloud:/Tools/${OS_VERSION}/"
# Virtualization:Containers has confd
ARG CONTAINERS_REPO="http://download.opensuse.org/repositories/home:/blgardner:/branches:/Virtualization:/containers/${OS_VERSION}/"
# blgardner's home repo is the current place to get forego
ARG FOREGO_REPO="http://download.opensuse.org/repositories/home:/blgardner/${OS_VERSION}/"
ARG PACKAGES="ceph<${CEPH_VERSION_NUM_UPPERBOUND} \
              ceph-radosgw<${CEPH_VERSION_NUM_UPPERBOUND} \
              rbd-mirror<${CEPH_VERSION_NUM_UPPERBOUND} \
              nfs-ganesha-ceph nfs-ganesha-rgw \
              etcd device-mapper e2fsprogs kubernetes-client \
              confd=$CONFD_VERSION forego"
RUN ( $ADDREPO $CEPH_REPO ceph-luminous && \
    $ADDREPO $CLOUD_REPO cloud-tools && \
    $ADDREPO $CONTAINERS_REPO virtualization-containers && \
    $ADDREPO $FOREGO_REPO forego && \
    $PACKAGE_MANAGER --gpg-auto-import-keys refresh && \
    $INSTALL $PACKAGES && \
    $PACKAGE_MANAGER info $PACKAGES && \
    $PACKAGE_MANAGER clean --all ) || \
    ( retval=$? && cat /var/log/zypper.log && exit $retval )

# Add s3cfg file
ADD s3cfg /root/.s3cfg

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
    rm -f /generate_entrypoint.sh && \
    bash -n /*.sh

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph", "/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
