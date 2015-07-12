# DOCKER-VERSION 1.0.0
#
# Ceph Daemon
#
# VERSION 0.0.1

FROM ceph/base
MAINTAINER Sébastien Han "seb@redhat.com"

RUN apt-get update && apt-get -y install runit && \
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh
ADD config.*.sh /

ADD my_init/my_init /sbin/my_init
RUN chmod +x /sbin/my_init
RUN mkdir -p /etc/container_environment

ADD 2.sh /etc/runit/2
RUN chmod +x /etc/runit/2

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
