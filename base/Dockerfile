# CEPH BASE IMAGE
# CEPH VERSION: Infernalis
# CEPH VERSION DETAIL: 9.2.x

FROM ubuntu:14.04
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION infernalis

# Install prerequisites
RUN apt-get update && \
    apt-get install -y python python-dev python-pip wget unzip uuid-runtime git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Ansible
RUN pip install ansible

# Install Ceph
RUN wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add -
RUN echo deb http://ceph.com/debian-${CEPH_VERSION}/ trusty main | tee /etc/apt/sources.list.d/ceph-${CEPH_VERSION}.list
RUN apt-get update && apt-get install -y --force-yes ceph radosgw && \
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /opt/ansible/
RUN cd /opt/ansible/ && git clone https://github.com/ceph/ceph-ansible
ADD site.yml /opt/ansible/ceph-ansible/site.yml

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
