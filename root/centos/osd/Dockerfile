# DOCKER-VERSION 1.0.0
# 
# Ceph OSD
#
#  USAGE NOTES:
#    * OSD_ID (numeric identifier for this OSD; obtain from `ceph osd create`)
#
# VERSION 0.0.2

FROM ceph/centos-base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Expose the ceph OSD port (6800+, by default)
EXPOSE 6800

RUN curl -L -o runit-2.1.1-7.el7.centos.x86_64.rpm "https://packagecloud-repositories.s3.amazonaws.com/83/295/el/7/package_files/446.rpm?AWSAccessKeyId=AKIAI44QGWC7C5WEV4XA&Signature=ziQokUFfzZKkZmLGAO1aAnqiXng%3D&Expires=1433783666"
RUN rpm -i runit-2.1.1-7.el7.centos.x86_64.rpm

ADD my_init/my_init /sbin/my_init
RUN chmod +x /sbin/my_init
RUN mkdir -p /etc/container_environment

ADD 2.sh /etc/runit/2
RUN chmod +x /etc/runit/2

RUN mkdir /etc/service/bootstrap
ADD entrypoint.sh /etc/service/bootstrap/run
RUN chmod +x /etc/service/bootstrap/run

ENTRYPOINT ["/sbin/my_init"]
