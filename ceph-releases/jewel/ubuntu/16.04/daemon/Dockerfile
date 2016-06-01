# DOCKER-VERSION 1.0.0
#
# Ceph Daemon
#
# VERSION 0.0.1

FROM ceph/base:tag-build-master-jewel-ubuntu-16.04
MAINTAINER Sébastien Han "seb@redhat.com"

# Add bootstrap script, ceph defaults key/values for KV store
ADD entrypoint.sh config.*.sh ceph.defaults /

ADD my_init/my_init /sbin/my_init
ADD 2.sh /etc/runit/2

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

RUN chmod +x /sbin/my_init && \
    mkdir -p /etc/container_environment && \
    chmod +x /etc/runit/2

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
