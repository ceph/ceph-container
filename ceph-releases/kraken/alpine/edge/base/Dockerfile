# CEPH BASE IMAGE
# CEPH VERSION: Kraken
# CEPH VERSION DETAIL: 11.0.x

FROM alpine:edge
MAINTAINER John Coyle "dx9err@gmail.com"

ENV CEPH_VERSION kraken
ENV CEPH_RELEASE 11.0.1-r2

# install prerequisites
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    apk --update add bash confd etcd jq runit \
    ceph=${CEPH_RELEASE} \
    ceph-radosgw=${CEPH_RELEASE} \
    rbd-mirror=${CEPH_RELEASE} && \
    rm -rf /var/cache/apk/*

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
