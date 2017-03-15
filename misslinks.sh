#!/bin/bash

# This software aims at detecting links which are not properly setup between releases.
# It does search in every ceph-release, in every OS and OS version if a file
# does exist in one but not the other.
# If so, the name of the existing & missing file is printed.
# It's then up to human to define what to do

function all_distro_but_me {
  echo $1 | sed -e "s|$2||g"
}

# Go to ceph-releases directory
pushd ceph-releases &>/dev/null

# By default, we check all ceph releases
all_releases=$(find . -maxdepth 1 -type d | grep -v "^.$")

# If some arguments are passed, let's consider them as some ceph releases
if [ $# -gt 0 ]; then
  all_releases="$@"
fi

for release in $all_releases ; do
  pushd $release &>/dev/null
  all_distributions=$(find . -mindepth 2 -maxdepth 2 -type d | grep -v "^.$" | sed -e 's|\./||g' |tr '\n' ' ')
    for distribution in $all_distributions; do
      other_distros=$(all_distro_but_me "$all_distributions" "$distribution")
      #echo "$release: $distribution: $other_distros"
      for local_file in $(find -L $distribution -type f| grep -v "^.$" | sed -e 's|\./|/|g' |tr '\n' ' '); do
        for other_distro in $other_distros; do
          base_file=$(echo "$local_file" | sed -e "s|$distribution||g")
          # Let's ignore vim swap files
          [[ $local_file =~ ^..*.swp$ ]] && continue
          target_file=$other_distro$base_file
          if [ ! -e $target_file ]; then
            echo "$release/$target_file doesn't exist but found in $release/$local_file"
          fi
        done
      done
   done
  popd &>/dev/null
done
