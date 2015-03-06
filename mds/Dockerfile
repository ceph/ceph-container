# DOCKER-VERSION 1.0.0
# 
# VERSION 0.0.2

FROM ceph/base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh

# Expose the ceph mds port (6800, by default)
EXPOSE 6800

# Execute monitor as the entrypoint
#WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
