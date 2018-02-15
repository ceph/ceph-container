# CEPH DAEMON IMAGE

FROM ceph/daemon-base:luminous-ubuntu-16.04-amd64
MAINTAINER Sébastien Han "seb@redhat.com"

ENV CEPH_VERSION luminous

#======================================================
# Add ceph-container script files
#======================================================

# Add bootstrap script, ceph defaults key/values for KV store
# This will also add any new *.sh scripts added by overrides
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
ARG CONFD_VERSION=0.10.0
ARG KUBECTL_VERSION=v1.6.0

# Packages list
ARG PACKAGES="sharutils etcd s3cmd nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw lvm2"

# Escape char after immediately after RUN allows comment in first line
RUN ( \
    # Install prerequisites
DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wget unzip uuid-runtime python-setuptools udev dmsetup && \
echo "deb http://download.ceph.com/nfs-ganesha/deb-V2.5-stable/luminous/ xenial main" | tee /etc/apt/sources.list.d/nfs-ganesha.list && \
apt-get update && apt-get install -y  --no-install-recommends --force-yes $PACKAGES && \
dpkg -s $PACKAGES && \
apt-get clean && \
# Download & install confd
wget -O /usr/local/bin/confd "https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VERSION}/confd-${CONFD_VERSION}-linux-amd64" && \
chmod +x /usr/local/bin/confd && mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates && \
# Install forego
wget -O /forego.tgz 'https://bin.equinox.io/c/ekMN3bCZFUn/forego-stable-linux-amd64.tgz' && \
cd /usr/local/bin && tar xfz /forego.tgz && chmod +x /usr/local/bin/forego && rm /forego.tgz && \
# Install kubectl
wget -O /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
chmod +x /usr/local/bin/kubectl && \
# Cleaning container
bash /ubuntu-specific_clean_container.sh && rm /ubuntu-specific_clean_container.sh ) && \
    # Clean container
    bash /clean_container_common.sh && rm /clean_container_common.sh && \
    bash /clean_ceph.sh && rm /clean_ceph.sh


#======================================================
# Add remaining ceph-container files
#======================================================

# Add s3cfg file
ADD s3cfg /root/.s3cfg

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
  rm -f /generate_entrypoint.sh && \
  bash -n /*.sh

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
