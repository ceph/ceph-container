# RHCS containerization

## Clone

git clone https://your_github_id:your_github_password@github.com/roofmonkey/rhcs

## build docker image

```console
docker build -t rhcs .
```

## prepare

```console
mkdir -p /etc/ceph
# for /var/lib/ceph
mkdir -p /srv/ceph-var
# directory for osd 0
mkdir -p /srv/ceph
# directory for osd 1
mkdir -p /srv/ceph-1
rm -rf /etc/ceph/* /srv/ceph/* /srv/ceph-1/*
```

## start Ceph mon
```console
docker run -ti --net=host -e MON_IP=10.1.4.12  -e CEPH_PUBLIC_NETWORK=10.1.4.0/24 -e CEPH_DAEMON=mon -e  -v /etc/ceph:/etc/ceph -v /srv/ceph-var:/var/lib/ceph rhcs
```

## start Ceph osd 0

```console
docker run -ti --privileged --net=host -e MON_IP=10.1.4.12  -e CEPH_PUBLIC_NETWORK=10.1.4.0/24 -e CEPH_DAEMON=osd -e  OSD_TYPE=directory -v /srv/ceph:/var/lib/ceph/osd/ -v /etc/ceph:/etc/ceph -v /srv/ceph-var:/var/lib/ceph rhcs
```

## start Ceph osd 1
```console
docker run -ti --privileged --net=host -e MON_IP=10.1.4.12  -e CEPH_PUBLIC_NETWORK=10.1.4.0/24 -e CEPH_DAEMON=osd -e  OSD_TYPE=directory -v /srv/ceph-1:/var/lib/ceph/osd/ -v /etc/ceph:/etc/ceph -v /srv/ceph-var:/var/lib/ceph rhcs
```
