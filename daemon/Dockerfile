# DOCKER-VERSION 1.0.0
#
# Ceph Daemon
#
# VERSION 0.0.1

FROM ceph/base
MAINTAINER Sébastien Han "seb@redhat.com"

# patch is only needed until PR #7351 is merged in ceph/ceph (and backported
# to the version used in ceph/ceph-docker)
RUN apt-get update && apt-get -y install runit patch sharutils && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add bootstrap script, ceph defaults key/values for KV store
# Also add patch to ceph-disk.  This can be removed once PR #7351 is merged
# in ceph/ceph (and backported to the version used by ceph/ceph-docker)
ADD entrypoint.sh config.*.sh ceph-disk.patch ceph.defaults /

ADD my_init/my_init /sbin/my_init
ADD 2.sh /etc/runit/2

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

RUN chmod +x /sbin/my_init && \
    mkdir -p /etc/container_environment && \
    chmod +x /etc/runit/2 && \
\
# Patch out ceph-disk, to allow overrides to user and group names
# This can be removed once PR #7351 is merged in ceph/ceph (and backported to
# the version used by ceph/ceph-docker)
    cd /usr/sbin && patch -p1 -n -u < /ceph-disk.patch

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
