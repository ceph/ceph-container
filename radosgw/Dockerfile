# DOCKER-VERSION 1.0.0
#
# Ceph rados gateway
#
# VERSION 0.0.1

FROM ceph/base:hammer
MAINTAINER Sébastien Han "seb@redhat.com"

# Install Rados gateway
RUN apt-get update && apt-get install -y --force-yes radosgw && \
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add the entrypoint script
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Expose Rados gateway embedded webserver port
EXPOSE 80
