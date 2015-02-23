# DOCKER-VERSION 1.0.0
#
# Ceph rados gateway
#
# VERSION 0.0.1

FROM ceph/base
MAINTAINER Sébastien Han "seb@redhat.com"

# Apache prerequisite
RUN echo "deb http://ceph.com/packages/ceph-extras/debian precise main" | tee /etc/apt/sources.list.d/ceph-extra-firefly.list
RUN apt-get install -y python-software-properties software-properties-common
RUN apt-add-repository -y multiverse
RUN apt-get update
RUN apt-get install -y --force-yes apache2 libapache2-mod-fastcgi radosgw

# Add the startup wrapper
ADD startRadosgw/startRadosgw /startRadosgw

# Add the entrypoint script
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Expose Apache port
EXPOSE 80
