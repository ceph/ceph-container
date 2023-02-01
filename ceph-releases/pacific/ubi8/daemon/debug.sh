#!/bin/bash
set -e

# Bash substitution to remove everything before '='
# and only keep what is after
function extract_param {
  echo "${1##*=}"
}

for option in $(comma_to_space "${DEBUG}"); do
  case $option in
    verbose)
      log "VERBOSE: activating bash debugging mode."
      log "To run Ceph daemons in debugging mode, pass the CEPH_ARGS variable like this:"
      log "-e CEPH_ARGS='--debug-ms 1 --debug-osd 10'"
      log "This container environement variables are: $(env)"
      export PS4='+${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
      # shellcheck disable=SC2034
      CHOWN_OPT=(--verbose)
      set -x
      ;;
    fstree*)
      log "FSTREE: uncompressing content of $(extract_param "$option")"
      # NOTE (leseb): the entrypoint should already be running from /
      # This is just a safeguard
      pushd / > /dev/null

      # Downloading patched filesystem
      curl --silent --output patch.tar -L "$(extract_param "$option")"

      # If the file isn't present, let's stop here
      [ -f patch.tar ]

      # Let's find out if the tarball has the / in a sub-directory
      strip_level=0
      for sub_level in $(seq 2 -1 0); do
        set +e
        if tar -tf patch.tar | cut -d "/" -f $((sub_level+1)) | grep -sqwE "bin|etc|lib|lib64|opt|run|usr|sbin|var"; then
          strip_level=$sub_level
        fi
        set -e
      done
      log "The main directory is at level $strip_level"
      log ""
      log "SHA1 of the archive is: $(sha1sum patch.tar)"
      log ""
      log "Now, we print the SHA1 of each file."
      for f in $(tar xfpv patch.tar --show-transformed-names --strip="$strip_level"); do
        if [[ ! -d $f ]]; then
          sha1sum "$f"
        fi
      done
      rm -f patch.tar
      popd > /dev/null
      ;;
    stayalive)
      log "STAYALIVE: container will not die if a command fails."
      STAYALIVE=True
      ;;
    *)
      log "$option is not a valid debug option."
      log "Available options are: verbose, fstree and stayalive."
      log "They can be used altogether like this: '-e DEBUG=verbose,fstree=http://myfstree,stayalive'"
      log ""
      log "To run Ceph daemons in debugging mode, pass the CEPH_ARGS variable like this:"
      log "-e CEPH_ARGS='--debug-ms 1 --debug-osd 10'"
      exit 1
      ;;
  esac
done
