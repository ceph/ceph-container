# CEPH DAEMON IMAGE
# CEPH VERSION: Jewel
# CEPH VERSION DETAIL: 10.2.x

FROM BASEIMAGE
MAINTAINER Sébastien Han "seb@redhat.com"

ENV ETCDCTL_VERSION v2.2.4
ENV ETCDCTL_ARCH linux-amd64
ENV CONFD_VERSION 0.10.0
ENV KUBECTL_VERSION v1.6.0

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

# install prerequisites
RUN # Download & install confd \
  wget -O /usr/local/bin/confd "https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64" && \
  chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates && \
  # Install forego \
  wget -O /forego.tgz 'https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-amd64.tgz' && \
  cd /usr/local/bin && tar xfz /forego.tgz && chmod +x /usr/local/bin/forego && rm /forego.tgz && \
  # Install kubectl \
  wget -O /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
  chmod +x /usr/local/bin/kubectl && \
  wget -q -O- "https://github.com/coreos/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}.tar.gz" |tar xfz - -C/tmp/ etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl && \
  mv /tmp/etcd-${ETCDCTL_VERSION}-${ETCDCTL_ARCH}/etcdctl /usr/local/bin/etcdctl && \
  chmod +x /usr/local/bin/etcdctl && \
  bash /clean_container.sh && rm -f /clean_container.sh

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
  rm -f /generate_entrypoint.sh && \
  bash -n /*.sh

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
