#!/usr/bin/env python

import boto
import boto.s3.connection

access_key = 'XXXXXXXXXXXXXXXXXXXX'
secret_key = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

conn = boto.connect_s3(
        aws_access_key_id = access_key,
        aws_secret_access_key = secret_key,
        host = '0.0.0.0',
        port = None,     # Leave as None to use default port 80 or 443
        is_secure=False, # comment out or set to True if you are using ssl
        calling_format = boto.s3.connection.OrdinaryCallingFormat(),
        )

bucket = conn.create_bucket('my-s3-test-bucket')

for bucket in conn.get_all_buckets():
    print "{name}\t{created}".format(
        name = bucket.name,
        created = bucket.creation_date,
    )

key = bucket.new_key('hello.txt')
key.set_contents_from_string('Hello World!\n')

hello_key = bucket.get_key('hello.txt')
hello_key.set_canned_acl('public-read')

key = bucket.new_key('secret_plans.txt')
key.set_contents_from_string('My secret plans!\n')

plans_key = bucket.get_key('secret_plans.txt')
plans_key.set_canned_acl('private')

hello_key = bucket.get_key('hello.txt')
hello_url = hello_key.generate_url(0, query_auth=False, force_http=False)
print hello_url

plans_key = bucket.get_key('secret_plans.txt')
plans_url = plans_key.generate_url(3600, query_auth=True, force_http=False)
print plans_url
