# DOCKER-VERSION 1.2.0
# VERSION 0.1.0
# 
# rbd-lock - acquire the given lock and (optionally) store its locker value in etcd
#

FROM ceph/rbd
MAINTAINER Seán C McCord "ulexus@gmail.com"

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Execute the lock script
ENTRYPOINT ["/entrypoint.sh"]
