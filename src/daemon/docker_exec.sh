#!/bin/bash

# use -E so that trap ERR works with set -e
set -E

function do_stayalive {
  if [ -z "$STAYALIVE" ]; then
    return
  fi

  set +x
  declare -F err_cleanup && err_cleanup

  CONTAINER_ID=$(sed -n 's|.*/[docker|libpod]*-\(.*\).scope$|\1|p' /proc/self/cgroup |uniq)

  echo "An issue occured and you asked me to stay alive."
  echo "You can connect to me with: sudo docker exec -i -t $CONTAINER_ID /bin/bash"
  echo "The current environment variables will be reloaded by this bash to be in a similar context."
  echo "When debugging is over stop me with: pkill sleep"
  echo "I'll sleep endlessly waiting for you darling, bye bye"

  # exporting current environement so the next bash will be in the same setup
  env | while IFS= read -r value; do
    echo "export $value" >> /root/.bashrc
  done

  sleep infinity
}

child_for_exec=1

function teardown {
  # Disabling the traps to avoid a cascading
  trap - SIGINT SIGILL SIGABRT SIGFPE SIGSEGV SIGTERM SIGBUS SIGCHLD SIGKILL ERR

  # This function is called when we got a signal reporting something died
  # It will check the child_for_exec process exited
  # Then it will execute the optional sigterm_cleanup_post and return the passed exit code
  local signal_name=$1
  local exit_code=$2
  echo "teardown: managing teardown after $signal_name"

  # If we receive SIGTERM, it means the process is supposed to still be alive
  # So let's call sigterm_cleanup_pre if any defined
  if [ "$signal_name" = "SIGTERM" ]; then
    declare -F sigterm_cleanup_pre && sigterm_cleanup_pre
  fi

  # Sending the TERM signal to the exec'd program
  # If we got a SIGTERM, that is propagating the signal,
  # If we got any other signal, we need to teardown as the stability is no more guaranteed
  [ -e /proc/$child_for_exec ] && (echo "teardown: Sending SIGTERM to PID $child_for_exec"; kill -TERM "$child_for_exec" 2>/dev/null)

  echo -n "teardown: Waiting PID $child_for_exec to terminate "
  local MAX_TIMEOUT=50
  local timeout=0
  while [ -e /proc/$child_for_exec ]; do
    echo -n "."
    sleep .1
    timeout=$(($timeout + 1))
    if [ $timeout -eq $MAX_TIMEOUT ]; then
      echo "<!>"
      echo "teardown: TIMEOUT ! Let's consider it died and continue. Container will be reported in error."
      exit_code=-1
      break;
    fi
  done
  echo
  echo "teardown: Process $child_for_exec is terminated"

  if [[ "$signal_name" =~ SIGTERM|SIGCHLD ]]; then
    # Execute the cleanup post-script if any is declared
    declare -F sigterm_cleanup_post && sigterm_cleanup_post
  else
    # Execute some user defined code if the exec'd process fails
    declare -F trap_exec_failure && trap_exec_failure
  fi

  do_stayalive

  echo "teardown: Bye Bye, container will die with return code $exit_code"
  if [[ $exit_code -ne "0" ]]; then
    echo "teardown: if you don't want me to die and have access to a shell to debug this situation, next time run me with '-e DEBUG=stayalive'"
  fi
  exit $exit_code
}

function _int {
  teardown "SIGINT" -1
}

function _ill {
  teardown "SIGILL" -1
}

function _abrt {
  teardown "SIGABRT" -1
}

function _fpe {
  teardown "SIGFPE" -1
}

function _segv {
  teardown "SIGSEGV" -1
}

function _term {
  teardown "SIGTERM" 0
}

function _bus {
  teardown "SIGBUS" -1
}

function _chld {
  teardown "SIGCHLD" 0
}

function _err {
  local lineno=$1
  local msg=$2
  local parent=$3
  local r=$4
  echo "Failed at $lineno: $msg on parent $parent with return code $r"
  # 143 usually means the application caught a SIGTERM signal, meaning the process was killed.
  if [ "$r" -eq 143 ]; then
    teardown "SIGTERM" 0
  else
    teardown "ERR" -1
  fi
  }

function exec {
  # This function overrides the built-in exec() call
  # It starts the process in background to catch ERR but
  # as per docker requirement, forward the SIGTERM to it.
  trap _int SIGINT
  trap _ill SIGILL
  trap _abrt SIGABRT
  trap _fpe SIGFPE
  trap _segv SIGSEGV
  trap _term SIGTERM
  trap _bus SIGBUS
  trap _chld SIGCHLD
  trap '_err ${LINENO} "$BASH_COMMAND" "$PPID" "$?"' ERR

  # Running the program in background and save the pid in child_for_exec
  "$@" &
  child_for_exec=$!

  echo "exec: PID $child_for_exec: spawning $*"
  echo "exec: Waiting $child_for_exec to quit"
  wait $child_for_exec

  # We should not reach that point as a SIGCHLD should be emitted
  # Just keep a protection "in-case-of"
  teardown "QUIT" -1
}
