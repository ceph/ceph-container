#!/bin/bash
set -e

IS_MGR_AVAIL=$(ceph "${CLI_OPTS[@]}" mgr dump | $PYTHON -c "import json, sys; print(json.load(sys.stdin)['available'])")
if [ "${IS_MGR_AVAIL}" == "True" ]; then
  exit 0
else
  exit 1
fi
