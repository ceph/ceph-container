#!/bin/bash

ceph --cluster "${CLUSTER}" mon remove "$(hostname -s)"
