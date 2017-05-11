#!/bin/bash
function list_dirs () {
  find . -maxdepth 1 -type d | tail -n +2 | sed 's|^./||g'
}

function build_charts () {
  echo "Building Charts"
  list_dirs | while read CHART; do
    if [ -f "${CHART}/Makefile" ]; then make -C "${CHART}"; fi
    if [ -f "${CHART}/requirements.yaml" ]; then helm dep up "${CHART}"; fi
    if [ -f "${CHART}/Chart.yaml" ]; then 
      helm package "./${CHART}"
    fi
  done
}


build_charts
