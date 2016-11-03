#!/bin/python
import os
import struct
import time
import base64

key = os.urandom(16)
header = struct.pack(
    '<hiih',
    1,                 # le16 type: CEPH_CRYPTO_AES
    int(time.time()),  # le32 created: seconds
    0,                 # le32 created: nanoseconds,
    len(key),          # le16: len(key)
)
print(base64.b64encode(header + key).decode('ascii'))
