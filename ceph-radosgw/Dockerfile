# DOCKER-VERSION 1.0.0
# 
# Ceph rados gateway
#
# VERSION 0.0.1

FROM ulexus/ceph-base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Expose the ceph OSD port (6800+, by default)
EXPOSE 80
EXPOSE 443

ADD entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["radosgw"]
