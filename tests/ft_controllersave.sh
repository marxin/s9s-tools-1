#! /bin/bash
MYNAME=$(basename $0)
MYBASENAME=$(basename $0 .sh)
MYDIR=$(dirname $0)
STDOUT_FILE=ft_errors_stdout
VERBOSE=""
VERSION="1.0.0"

LOG_OPTION="--wait"
DEBUG_OPTION=""

CLUSTER_NAME_GALERA="galera_$$"
CLUSTER_NAME_POSTGRESQL="postgresql_$$"
CLUSTER_ID=""

PIP_CONTAINER_CREATE=$(which "pip-container-create")
CONTAINER_SERVER=""

OPTION_INSTALL=""
OPTION_NUMBER_OF_NODES="1"
OPTION_VENDOR="percona"

# The IP of the node we added first and last. Empty if we did not.
FIRST_ADDED_NODE=""
LAST_ADDED_NODE=""
SECONDARY_CONTROLLER_IP=""
SECONDARY_CONTROLLER_URL=""
SSH_PID=""
OUTPUT_DIR="${HOME}/cmon-saved-clusters"
OUTPUT_FILE="${MYBASENAME}_$$.tgz"

WITH_CLUSTER_GALERA=""
WITH_CLUSTER_POSTGRE="true"

cd $MYDIR
source ./include.sh
source ./shared_test_cases.sh

PROVIDER_VERSION=$PERCONA_GALERA_DEFAULT_PROVIDER_VERSION

#
# Prints usage information and exits.
#
function printHelpAndExit()
{
cat << EOF
Usage: 
  $MYNAME [OPTION]... [TESTNAME]
 
  $MYNAME - Test script for s9s to check controller save/restore features. 

  -h, --help       Print this help and exit.
  --verbose        Print more messages.
  --log            Print the logs while waiting for the job to be ended.
  --server=SERVER  The name of the server that will hold the containers.
  --print-commands Do not print unit test info, print the executed commands.
  --install        Just install the cluster and exit.
  --reset-config   Remove and re-generate the ~/.s9s directory.
  --vendor=STRING  Use the given Galera vendor.
  --leave-nodes    Do not destroy the nodes at exit.
  --galera         The test cluster should be a galera cluster (default).
  --postgres       The test cluster should be a postgresql cluster.
  
  --provider-version=VERSION The SQL server provider version.
  --number-of-nodes=N        The number of nodes in the initial cluster.

SUPPORTED TESTS:
  o createController     Creates a second controller in a container.
  o testCreateGalera     Creates a Galera cluster to be saved.
  o testCreatePostgre    Creates a PostgreSQL cluster as an alternaive.
  o testSave             Saves the controller.
  o testRestore          Restores controller.
  o cleanup              Cleans up previously allocated resources.

EXAMPLE
 ./$MYNAME --print-commands --server=core1 --reset-config --install

EOF
    exit 1
}

ARGS=$(\
    getopt -o h \
        -l "help,verbose,log,server:,print-commands,install,reset-config,\
galera,postgres,\
provider-version:,number-of-nodes:,vendor:,leave-nodes" \
        -- "$@")

if [ $? -ne 0 ]; then
    exit 6
fi

eval set -- "$ARGS"
while true; do
    case "$1" in
        -h|--help)
            shift
            printHelpAndExit
            ;;

        --verbose)
            shift
            VERBOSE="true"
            ;;

        --log)
            shift
            LOG_OPTION="--log"
            DEBUG_OPTION="--debug"
            ;;

        --server)
            shift
            CONTAINER_SERVER="$1"
            shift
            ;;

        --print-commands)
            shift
            DONT_PRINT_TEST_MESSAGES="true"
            PRINT_COMMANDS="true"
            ;;

        --install)
            shift
            OPTION_INSTALL="--install"
            ;;

        --reset-config)
            shift
            OPTION_RESET_CONFIG="true"
            ;;

        --galera)
            shift
            WITH_CLUSTER_GALERA="true"
            ;;

        --postgres)
            shift
            WITH_CLUSTER_POSTGRE="true"
            ;;

        --provider-version)
            shift
            PROVIDER_VERSION="$1"
            shift
            ;;

        --number-of-nodes)
            shift
            OPTION_NUMBER_OF_NODES="$1"
            shift
            ;;
        
        --vendor)
            shift
            OPTION_VENDOR="$1"
            shift
            ;;

        --leave-nodes)
            shift
            OPTION_LEAVE_NODES="true"
            ;;

        --)
            shift
            break
            ;;
    esac
done

function ssh_to_controller()
{
    echo "Executing ssh \"$SECONDARY_CONTROLLER_IP\" bash --login -c \"$*\""
    ssh -o ConnectTimeout=1 \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o LogLevel=quiet \
        "$SECONDARY_CONTROLLER_IP" \
        -- "bash --login -c \"$*\""
}

#
# This test will allocate a few nodes and install a new cluster.
#
function testCreateGalera()
{
    local nodes
    local node_ip
    local exitCode
    local node_serial=1
    local node_name

    print_title "Creating a Galera Cluster"
    if [ -z "$WITH_CLUSTER_GALERA" ]; then
        cat <<EOF
  The test is now executed for a non-galera cluster, skipping this step.
EOF
        return 0
    fi

    #
    #
    #
    begin_verbatim

    while [ "$node_serial" -le "$OPTION_NUMBER_OF_NODES" ]; do
        node_name=$(printf "${MYBASENAME}_gnode%03d_$$" "$node_serial")

        echo "Creating node #$node_serial"
        node_ip=$(create_node --autodestroy "$node_name")

        if [ -n "$nodes" ]; then
            nodes+=";"
        fi

        nodes+="$node_ip"

        if [ -z "$FIRST_ADDED_NODE" ]; then
            FIRST_ADDED_NODE="$node_ip"
        fi

        let node_serial+=1
    done
     
    #
    # Creating a Galera cluster.
    #
    mys9s cluster \
        --create \
        --cluster-type=galera \
        --nodes="$nodes" \
        --vendor="$OPTION_VENDOR" \
        --cluster-name="$CLUSTER_NAME_GALERA" \
        --provider-version=$PROVIDER_VERSION \
        --generate-key \
        $LOG_OPTION \
        $DEBUG_OPTION

    check_exit_code $?

    CLUSTER_ID=$(find_cluster_id $CLUSTER_NAME_GALERA)
    if [ "$CLUSTER_ID" -gt 0 ]; then
        printVerbose "Cluster ID is $CLUSTER_ID"
    else
        failure "Cluster ID '$CLUSTER_ID' is invalid"
    fi

    wait_for_cluster_started "$CLUSTER_NAME_GALERA"
    end_verbatim
}


function testCreatePostgre()
{
    local nodes
    local node_ip
    local exitCode
    local node_serial=1
    local node_name

    print_title "Creating a PostgreSQL Cluster"
    if [ -z "$WITH_CLUSTER_POSTGRE" ]; then
        cat <<EOF
  The test is now executed for a non-postgresql cluster, skipping this step.
EOF
        return 0
    fi

    #
    #
    #
    begin_verbatim

    while [ "$node_serial" -le "$OPTION_NUMBER_OF_NODES" ]; do
        node_name=$(printf "${MYBASENAME}_pnode%03d_$$" "$node_serial")

        echo "Creating node #$node_serial"
        node_ip=$(create_node --autodestroy "$node_name")

        if [ -n "$nodes" ]; then
            nodes+=";"
        fi

        nodes+="$node_ip"

        if [ -z "$FIRST_ADDED_NODE" ]; then
            FIRST_ADDED_NODE="$node_ip"
        fi

        let node_serial+=1
    done

    #
    # Creating a PostgreSql cluster.
    #
    mys9s cluster \
        --create \
        --cluster-type=postgresql \
        --nodes="$nodes" \
        --cluster-name="$CLUSTER_NAME_POSTGRESQL" \
        --provider-version="9.6" \
        --db-admin="postmaster" \
        --db-admin-passwd="passwd12" \
        --generate-key \
        $LOG_OPTION \
        $DEBUG_OPTION
    
    check_exit_code $?

    CLUSTER_ID=$(find_cluster_id $CLUSTER_NAME_POSTGRESQL)
    if [ "$CLUSTER_ID" -gt 0 ]; then
        printVerbose "Cluster ID is $CLUSTER_ID"
    else
        failure "Cluster ID '$CLUSTER_ID' is invalid"
    fi

    wait_for_cluster_started "$CLUSTER_NAME_POSTGRESQL"
    end_verbatim
}

function testSave()
{
    local tgz_file="$OUTPUT_DIR/$OUTPUT_FILE"

    print_title "Saving Controller"
    begin_verbatim

    mys9s cluster --list --long
    mys9s user --list --long

    mys9s backup \
        --save-controller \
        --backup-directory=$OUTPUT_DIR \
        --output-file=$OUTPUT_FILE \
        --log
    
    check_exit_code $?

    if [ ! -f "$tgz_file" ]; then
        failure "File '$tgz_file' was not created."
    else
        success "  o File '$tgz_file' was created, ok"
    fi
    end_verbatim
}

#
# Restoring the controller and checking everything.
#
function testRestore()
{
    local local_file="$OUTPUT_DIR/$OUTPUT_FILE"
    local remote_file="/tmp/$OUTPUT_FILE"
    local retcode

    print_title "Restoring Controller"
    begin_verbatim
    
    # Copying the tar.gz file to the secondary controller.
    scp "$local_file" "$SECONDARY_CONTROLLER_IP:$remote_file"
    check_exit_code_no_job $?

    # Restoring the cluster on the remote controller.
    mys9s backup \
        --restore-controller \
        --input-file=$remote_file \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret \
        --debug \
        --log

    check_exit_code $?
    end_verbatim

    #
    # Checking the cluster state after it is restored.
    #
    print_title "Waiting until Cluster(s) Started"
    begin_verbatim

    mysleep 20
    s9s cluster \
        --list \
        --long \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret

    if [ -n "$WITH_CLUSTER_GALERA" ]; then
        wait_for_cluster_started \
            --system \
            --controller "$SECONDARY_CONTROLLER_URL" \
            "$CLUSTER_NAME_GALERA"

        retcode=$?

        if [ "$retcode" -ne 0 ]; then
            failure "Cluster $CLUSTER_NAME_GALERA is not in started state."
        else
            success "  o The cluster $CLUSTER_NAME_GALERA is started, ok"
        fi
    fi
    
    if [ -n "$WITH_CLUSTER_POSTGRE" ]; then
        wait_for_cluster_started \
            --system \
            --controller "$SECONDARY_CONTROLLER_URL" \
            "$CLUSTER_NAME_POSTGRESQL"

        retcode=$?

        if [ "$retcode" -ne 0 ]; then
            failure "Cluster $CLUSTER_NAME_POSTGRESQL is not in started state."
        else
            success "  o The cluster $CLUSTER_NAME_POSTGRESQL is started, ok"
        fi
    fi

    s9s cluster \
        --stat \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret 
        
    s9s cluster \
        --list \
        --long \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret
    
    end_verbatim
}

function cleanup()
{
    print_title "Cleaning Up"
    begin_verbatim

    echo "PID for ssh: $SSH_PID"
    if [ -n "$SSH_PID" ]; then
        kill $SSH_PID 2>/dev/null >/dev/null
        sleep 3
        kill -9 $SSH_PID 2>/dev/null
    fi

    if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
        rm -f "$OUTPUT_DIR/$OUTPUT_FILE"
    fi
    
    end_verbatim
}

#
# Running the requested tests.
#
startTests

reset_config
grant_user

if [ "$OPTION_INSTALL" ]; then
    if [ -n "$1" ]; then
        for testName in $*; do
            runFunctionalTest "$testName"
        done
    else
        runFunctionalTest createController
        runFunctionalTest testCreateGalera
        runFunctionalTest testCreatePostgre
        runFunctionalTest testSave
        runFunctionalTest testRestore
    fi
elif [ "$1" ]; then
    for testName in $*; do
        runFunctionalTest "$testName"
    done
else
    runFunctionalTest createController    
    runFunctionalTest testCreateGalera
    runFunctionalTest testCreatePostgre
    runFunctionalTest testSave
    runFunctionalTest testRestore
    runFunctionalTest cleanup
fi

endTests

