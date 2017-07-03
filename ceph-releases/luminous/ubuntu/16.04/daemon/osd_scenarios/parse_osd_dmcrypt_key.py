import base64
import sys

for line in sys.stdin:
	sys.stdout.write(base64.b64decode(line.decode("utf-8")))
