#!/bin/bash
set -e

ceph --cluster "${CLUSTER}" mon remove "$(hostname -s)"
