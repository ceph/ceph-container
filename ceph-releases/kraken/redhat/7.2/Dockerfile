FROM  registry.access.redhat.com/rhel7.2

MAINTAINER Huamin Chen "hchen@redhat.com"

ENV CEPH_VERSION kraken

ENV container docker

# This need to be removed later
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

RUN yum-config-manager --add=http://download.eng.bos.redhat.com/devel/candidate-trees/latest-Ceph-2-RHEL-7/compose/MON/x86_64/os/
RUN yum-config-manager --add=http://download.eng.bos.redhat.com/devel/candidate-trees/latest-Ceph-2-RHEL-7/compose/OSD/x86_64/os/
RUN yum-config-manager --add=http://download.eng.bos.redhat.com/devel/candidate-trees/latest-Ceph-2-RHEL-7/compose/Tools/x86_64/os/
RUN yum-config-manager --add=http://pulp.dist.prod.ext.phx2.redhat.com/content/dist/rhel/server/7/7Server/x86_64/os/


RUN yum -y update; yum clean all; \
(cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*; \
yum -y install ceph-mon ceph-osd ceph-mds ceph-radosgw rbd-mirror nfs-ganesha-rgw --nogpgcheck; yum clean all

# Editing /etc/redhat-storage-server release file
RUN echo "Red Hat Ceph Storage Server 2.0 (Container)" > /etc/redhat-storage-release

EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph","/etc/ganesha"]

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh
ADD config.*.sh /

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]

# Atomic specific labels
ADD install.sh /install.sh
LABEL Version="2.0" Description="This image has a running Ceph daemon (RHEL 7.2 + RHCS 2.0)"
LABEL RUN="/usr/bin/docker run -d --net=host --pid=host -e MON_NAME=\${MON_NAME} -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \${IMAGE}"
LABEL INSTALL="/usr/bin/docker run --rm --privileged -v /:/host -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -e MON_NAME=\${MON_NAME} -e OSD_DEVICE=\${OSD_DEVICE} -e HOST=/host -e IMAGE=\${IMAGE} --entrypoint=/install.sh \${IMAGE}"
