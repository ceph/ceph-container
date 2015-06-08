# DOCKER-VERSION 1.0.0
#
# Ceph rados gateway
#
# VERSION 0.0.1

FROM ceph/base
MAINTAINER Sébastien Han "seb@redhat.com"

# Add the entrypoint script
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Expose Rados gateway embedded webserver port
EXPOSE 80
