# DOCKER-VERSION 1.0.0
# 
# VERSION 0.0.2

FROM ulexus/ceph-base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Fuse's mknod doesn't work with docker build
# Workaround from: https://github.com/dotcloud/docker/issues/514
RUN apt-get install -y --force-yes libfuse2 apt-utils
RUN mkdir -p /root/debbuild/fuse
WORKDIR /root/debbuild/fuse
RUN apt-get download -y fuse
RUN dpkg-deb -X fuse*.deb build
RUN dpkg-deb -e fuse*.deb build/DEBIAN
RUN rm *.deb
ADD fuse-postinst /root/debbuild/fuse/build/DEBIAN/postinst
ADD fuse-control /root/debbuild/fuse/build/DEBIAN/control
WORKDIR /root/debbuild/fuse/build
RUN dpkg-deb -b /root/debbuild/fuse/build /root/debbuild/fuse.deb
RUN dpkg -i /root/debbuild/fuse.deb
RUN ["echo", "fuse hold", "|" ,"dpkg", "--set-selections"]

# Install the metadata server
RUN apt-get install -y ceph-mds

# Add bootstrap script
ADD entrypoint.sh /usr/local/bin/entrypoint.sh

# Expose the ceph mds port (6800, by default)
EXPOSE 6800

# Execute monitor as the entrypoint
#WORKDIR /
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
