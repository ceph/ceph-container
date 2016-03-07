FROM busybox
MAINTAINER Matthew Hook "hookenz@gmail.com"

ADD ceph /
ADD ceph-disk /
ADD rados /
ADD rbd /
ADD startup.sh /
RUN mkdir -p /opt/bin
ENTRYPOINT ["/startup.sh"]
