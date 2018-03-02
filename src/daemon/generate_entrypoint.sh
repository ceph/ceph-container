#!/bin/bash
set -e

source variables_entrypoint.sh

# FUNCTIONS
function moving_on {
  echo "INFO: moving on, using default entrypoint.sh.in file as is."
  mv /entrypoint.sh.in /entrypoint.sh
  exit 0
}

function check_scenario_file {
  if [ -s /disabled_scenario ]; then
    source /disabled_scenario
    if [[ -z "$EXCLUDED_TAGS" ]]; then
      echo "INFO: the variable EXCLUDED_TAGS is missing from the disabled_scenario file."
      moving_on
    fi
  else
    # (leseb): it is obviously empty since we add it as part of the Dockerfile ADD statement
    # If we end up here, the file has been added but is empty (size non-greater than 0)
    echo "INFO: disabled_scenario file is empty, no scenario to disable."
    moving_on
  fi
}

function build_sed_regex {
  for tag in $EXCLUDED_TAGS; do
    SED_LINE="s/# TAG: $tag/unsupported_scenario/g; ${SED_LINE}"
    ALL_SCENARIOS="${ALL_SCENARIOS/$tag /}"

    # If it's the last of the chain there is no space after it so the previous substitution missed it
    ALL_SCENARIOS="${ALL_SCENARIOS/$tag/}"
  done
  # Remove trailing whitespace
  ALL_SCENARIOS="${ALL_SCENARIOS% }"
}

# MAIN
check_scenario_file
build_sed_regex

sed -i "s/ALL_SCENARIOS=.*/ALL_SCENARIOS='${ALL_SCENARIOS}'/" variables_entrypoint.sh
sed "${SED_LINE}" /entrypoint.sh.in > /entrypoint.sh
echo "INFO: entrypoint.sh successfully generated."
echo "INFO: the following scenario(s) was/were disabled: $EXCLUDED_TAGS."
chmod +x /entrypoint.sh
rm -f /entrypoint.sh.in /disabled_scenario
