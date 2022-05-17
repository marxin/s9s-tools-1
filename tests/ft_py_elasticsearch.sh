#!/bin/bash

# need to source all the env. Only exported variables will execute
source ./include.sh

# start tests (cleanups before test. example: clean backup folder)
startTests
reset_config
grant_user

# call python test (environment variables exported on include are visible for python test)
rm .pys9s_results_env 2>/dev/null
export USE_FT_FULL="YES"
python3 pys9s/ft_elasticsearch.py
# python test should fulfilled in all required environment variables on .pys9s_results_env
export $(grep -v '^#' .pys9s_results_env | xargs)

endTests
