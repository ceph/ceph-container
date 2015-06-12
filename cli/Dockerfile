FROM ceph/base
MAINTAINER Matthew Hook "hookenz@gmail.com"

ADD ceph /
ADD startup.sh /
RUN mkdir -p /opt/bin
ENTRYPOINT ["/startup.sh"]
