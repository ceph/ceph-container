# DOCKER-VERSION 1.2.0
# VERSION 0.1.0
# 
# rbd-unlock - release an RBD lock
#

FROM ceph/rbd
MAINTAINER Seán C McCord "ulexus@gmail.com"

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Execute the lock script
ENTRYPOINT ["/entrypoint.sh"]
