# DOCKER-VERSION 1.0.0
# 
# Ceph OSD
#
#  USAGE NOTES:
#    * OSD_ID (numeric identifier for this OSD; obtain from `ceph osd create`)
#
# VERSION 0.0.2

FROM ceph/base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Expose the ceph OSD port (6800+, by default)
EXPOSE 6800

ADD entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["ceph-osd"]
