# DOCKER-VERSION 1.4.1
# 
# Ceph RBD volume ambassador
#
#  USAGE NOTES:
#    - Set the RBD_POOL environment variable on run (-e RBD_POOL=poolname)
#    - Set the RBD_IMAGE environment variable on run (-e RBD_IMAGE=imagename)
#    - remember to reference the source config dir when running this container (e.g. `-v /etc/ceph:/etc/ceph`)
#
# VERSION 0.0.2

FROM ceph/base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Add mountWait
ADD mountWait/mountWait /mountWait
RUN chmod +x /mountWait

# Add entrypoint script
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
