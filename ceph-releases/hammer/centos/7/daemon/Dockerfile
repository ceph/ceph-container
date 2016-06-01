# DOCKER-VERSION 1.0.0
#
# Ceph Daemon
#
# VERSION 0.0.1

FROM ceph/base:tag-build-master-hammer-centos-7
MAINTAINER Sébastien Han "seb@redhat.com"

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh
ADD config.*.sh /

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# ceph defaults key/values for KV store
ADD ceph.defaults /

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
