FROM busybox
MAINTAINER Jason Murray "jason@murrayinfotech.com"

ADD ceph /
ADD ceph-disk /
ADD rados /
ADD rbd /

ADD startup.sh /
RUN mkdir -p /opt/bin
ENTRYPOINT ["/startup.sh"]
