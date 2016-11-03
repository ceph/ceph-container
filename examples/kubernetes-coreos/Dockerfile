FROM busybox
MAINTAINER Pat Christopher "coffeepac@gmail.com"

ADD ceph /
ADD rbd /
ADD rados /
ADD ceph-disk /
ADD ceph-rbdnamer /
ADD 50-rbd.rules /

ADD startup.sh /
RUN mkdir -p /opt/bin
RUN mkdir -p /etc/udev/rules.d/
ENTRYPOINT ["/startup.sh"]
