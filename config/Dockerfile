# DOCKER-VERSION 1.0.0
# 
# Ceph Config 
#
#  USAGE NOTES:
#    - Define at least the two following environment variables:
#      MONHOST - the hostname of this monitor
#      MONIP   - the (externally visible) IP address of this monitor
#    - /etc/ceph is set as a volume, so you may use a common configuration directory
#      among your ceph daemons (this also keeps private keys outside of the image)
#
# VERSION 0.0.1

FROM ceph/base
MAINTAINER Sébastien Han "seb@redhat.com"

RUN wget https://github.com/coreos/etcd/releases/download/v0.4.6/etcd-v0.4.6-linux-amd64.tar.gz
RUN tar xzvf etcd-v0.4.6-linux-amd64.tar.gz
RUN cp etcd-v0.4.6-linux-amd64/etcdctl /usr/local/bin

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh

# Add volumes for ceph config and monitor data
VOLUME ["/etc/ceph"]

# Execute monitor as the entrypoint
ENTRYPOINT ["/entrypoint.sh"]

