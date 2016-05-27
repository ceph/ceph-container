#!/bin/sh
if [ -z "$1" ]; then
  /bin/bash
else
  $@
fi
