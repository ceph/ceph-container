#!/bin/bash

function set_trap_err {
  # Let's propagate traps to all functions
  set -E

  # Let's call trap_error if we catch an ERR
  trap 'trap_error' ERR
}

NOTRAP=
function trap_error {
  set +x
  declare -F err_cleanup && err_cleanup
  if [ -z "$NOTRAP" ]; then
    echo "An issue occured and you asked me to stay alive."
    echo "You can connect to me with: sudo docker exec -i -t $HOSTNAME /bin/bash"
    echo "The current environment variables will be reloaded by this bash to be in a similar context."
    echo "When debugging is over stop me with: pkill sleep"
    echo "I'll sleep for 365 days waiting for you darling, bye bye"

    # exporting current environement so the next bash will be in the same setup
    env | while IFS= read -r value; do
      echo "export $value" >> /root/.bashrc
    done

    sleep 365d
  else
    # If NOTRAP is defined, we need to return true to avoid triggering an ERR
    true
  fi
}

child_for_exec=1

function teardown {
  # Disabling the traps to avoid a cascading
  trap - SIGINT SIGILL SIGABRT SIGFPE SIGSEGV SIGTERM SIGBUS SIGCHLD SIGKILL

  # This function is called when we got a signal reporting something died
  # It will check the child_for_exec process exited
  # Then it will execute the optional sigterm_cleanup_post and return the passed exit code
  local signal_name=$1
  local exit_code=$2
  echo "teardown: managing teardown after $signal_name"

  # Disabling the ERR trap before killing the process
  # That's an expected failure so don't handle it
  # Doing "trap ERR" or "trap - ERR" didn't worked :/
  NOTRAP="yes"

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

  if [ "$signal_name" = "SIGTERM" ]; then
    # Execute the cleanup post-script if any is declared
    declare -F sigterm_cleanup_post && sigterm_cleanup_post
  else
    # Execute some user defined code if the exec'd process fails
    declare -F trap_exec_failure && trap_exec_failure
  fi

  echo "teardown: Bye Bye, container will die with return code $exit_code"
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
  teardown "SIGCHLD" -1
}

function _kill {
  teardown "SIGKILL" -1
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
  trap _kill SIGKILL

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
