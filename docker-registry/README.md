# Docker-registry

```
docker run -d \
         --name ceph-docker-registry
         -e AWS_BUCKET=mybucket \
         -e AWS_KEY=myawskey \
         -e AWS_SECRET=myawssecret \
         -e AWS_HOST=myowns3.com \
         -e AWS_SECURE=true \
         -e AWS_PORT=80 \
         -e AWS_CALLING_FORMAT=boto.s3.connection.OrdinaryCallingFormat \
         -p 5000:5000 \
         ceph/docker-registry
```

In the example boto.s3.connection.OrdinaryCallingFormat makes API calls in the format:

```
http://HOST:PORT/BUCKET/OBJECT
```

if AWS_CALLING_FORMAT is empty, it calls like:

```
http://BUCKET.HOST:PORT/OBJECT
```

[`all options`](https://github.com/docker/docker-registry/blob/master/ADVANCED.md)
