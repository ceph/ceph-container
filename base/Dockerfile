# CEPH BASE IMAGE
# CEPH VERSION: Firefly
# CEPH VERSION DETAIL: 0.80.8


FROM ubuntu:14.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION firefly

# Install Ceph
CMD wget -q -O- 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc' | apt-key add -
RUN echo deb http://ceph.com/debian-$CEPH_VERSION/ trusty main | tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list
RUN apt-get update
RUN apt-get install -y --force-yes ceph
