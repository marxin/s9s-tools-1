#! /bin/bash
MYNAME=$(basename $0)
MYBASENAME=$(basename $0 .sh)
MYDIR=$(dirname $0)
STDOUT_FILE=ft_errors_stdout
VERBOSE=""
VERSION="1.0.0"

LOG_OPTION="--wait"
DEBUG_OPTION=""

CLUSTER_NAME="${MYBASENAME}_$$"
CLUSTER_ID=""

PIP_CONTAINER_CREATE=$(which "pip-container-create")
CONTAINER_SERVER=""

OPTION_INSTALL=""
OPTION_NUMBER_OF_NODES="3"
OPTION_VENDOR="percona"

# The IP of the node we added first and last. Empty if we did not.
FIRST_ADDED_NODE=""
LAST_ADDED_NODE=""
SECONDARY_CONTROLLER_IP=""
SECONDARY_CONTROLLER_URL=""
SSH_PID=""
OUTPUT_DIR="${HOME}/cmon-saved-clusters"
OUTPUT_FILE="${MYBASENAME}_$$.tgz"
CLUSTER_TYPE="galera"
#CLUSTER_TYPE="postgresql"

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
 
  $MYNAME - Test to check cluster save/restore on secondary controller. 

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
  o testCreateGalera     Creates a Galera cluster if requested.
  o testCreatePostgre    Creates a PostgreSQL cluster if requested.
  o testSaveCluster      Saves the cluster on the local controller.
  o testRestore          Loads the cluster on the remote controller.
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
            CLUSTER_TYPE="galera"
            ;;

        --postgres)
            shift
            CLUSTER_TYPE="postgresql"
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

    if [ "$CLUSTER_TYPE" != "galera" ]; then
        print_title "Creating a Galera Cluster is Not Done Here"
        return 0
    fi

    print_title "Creating a Galera Cluster"
    cat <<EOF
Creating a cluster that we will save and restore in the next steps. Creating
$OPTION_NUMBER_OF_NODES node(s).

EOF
    begin_verbatim

    while [ "$node_serial" -le "$OPTION_NUMBER_OF_NODES" ]; do
        node_name=$(printf "${MYBASENAME}_node%03d_$$" "$node_serial")

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
        --cluster-name="$CLUSTER_NAME" \
        --provider-version=$PROVIDER_VERSION \
        $LOG_OPTION \
        $DEBUG_OPTION

    exitCode=$?
    if [ "$exitCode" -ne 0 ]; then
        failure "Exit code is $exitCode while creating cluster."
        mys9s job --list
        mys9s job --log --job-id=1
        exit 1
    fi

    CLUSTER_ID=$(find_cluster_id $CLUSTER_NAME)
    if [ "$CLUSTER_ID" -gt 0 ]; then
        printVerbose "Cluster ID is $CLUSTER_ID"
    else
        failure "Cluster ID '$CLUSTER_ID' is invalid"
    fi

    wait_for_cluster_started "$CLUSTER_NAME"
    end_verbatim
}

function testCreatePostgre()
{
    local nodes
    local node_ip
    local exitCode
    local node_serial=1
    local node_name

    if [ "$CLUSTER_TYPE" != "postgresql" ]; then
        print_title "Creating a PostgreSQL Cluster is Not Done Here"
        return 0
    fi

    #
    #
    #
    print_title "Creating a PostgreSQL Cluster"
    cat <<EOF
Creating a cluster that we will save and restore in the next steps. Creating
$OPTION_NUMBER_OF_NODES node(s).
EOF
    begin_verbatim

    while [ "$node_serial" -le "$OPTION_NUMBER_OF_NODES" ]; do
        node_name=$(printf "${MYBASENAME}_node%03d_$$" "$node_serial")

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
        --cluster-name="$CLUSTER_NAME" \
        --provider-version="9.5" \
        --db-admin="postmaster" \
        --db-admin-passwd="passwd12" \
        --generate-key \
        $LOG_OPTION \
        $DEBUG_OPTION
    
    exitCode=$?
    if [ "$exitCode" -ne 0 ]; then
        failure "Exit code is $exitCode while creating cluster."
        mys9s job --list
        mys9s job --log --job-id=1
        exit 1
    fi

    CLUSTER_ID=$(find_cluster_id $CLUSTER_NAME)
    if [ "$CLUSTER_ID" -gt 0 ]; then
        printVerbose "Cluster ID is $CLUSTER_ID"
    else
        failure "Cluster ID '$CLUSTER_ID' is invalid"
    fi

    wait_for_cluster_started "$CLUSTER_NAME"
    end_verbatim
}

function testSaveCluster()
{
    local tgz_file="$OUTPUT_DIR/$OUTPUT_FILE"

    print_title "Saving Cluster"
    cat <<EOF
Saving the cluster on the local controller into a tarball. Checking if the
output file was created.
EOF
    begin_verbatim

    mys9s backup \
        --save-cluster-info \
        --cluster-id=1 \
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
# Restoring and checking.
#
function testRestore()
{
    local local_file="$OUTPUT_DIR/$OUTPUT_FILE"
    local remote_file="/tmp/$OUTPUT_FILE"
    local retcode

    print_title "Restoring Cluster on $SECONDARY_CONTROLLER_IP"
    cat <<EOF
This test will restore the saved cluster on a different controller (the
secondary controller on $SECONDARY_CONTROLLER_IP. 
EOF
    begin_verbatim

    # Copying the tar.gz file to the secondary controller.
    echo "scp \"$local_file\" \"$SECONDARY_CONTROLLER_IP:$remote_file\""
    scp "$local_file" "$SECONDARY_CONTROLLER_IP:$remote_file"
    check_exit_code_no_job $?
    
    # Restoring the cluster on the remote controller.
    mys9s backup \
        --restore-cluster-info \
        --input-file=$remote_file \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret \
        --log

    check_exit_code $?
    end_verbatim

    #
    #
    #
    print_title "Waiting until Cluster $CLUSTER_NAME is Started"

    cat <<EOF
Checking that the socondary controller ($SECONDARY_CONTROLLER_IP) is able to 
manage the cluster. If so the cluster should be in STARTED state.
EOF
    begin_verbatim

    wait_for_cluster_started \
        --system \
        --controller $SECONDARY_CONTROLLER_URL \
        "$CLUSTER_NAME"

    retcode=$?

    s9s cluster \
        --stat \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret 
    
    s9s node \
        --list \
        --long \
        --controller=$SECONDARY_CONTROLLER_URL \
        --cmon-user=system \
        --password=secret

    if [ "$retcode" -ne 0 ]; then
        failure "Cluster is not is started state."
    else
        success "  o The cluster is in started state, ok"
    fi

    end_verbatim
}

function cleanup()
{
    print_title "Cleaning Up"
    cat <<EOF
Releasing previously allocated resources, deleting files, killing processes.
EOF
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
        runFunctionalTest testCreateGalera
        runFunctionalTest testCreatePostgre
    fi
elif [ "$1" ]; then
    for testName in $*; do
        runFunctionalTest "$testName"
    done
else
    runFunctionalTest createController
    runFunctionalTest testCreateGalera
    runFunctionalTest testCreatePostgre
    runFunctionalTest testSaveCluster
    runFunctionalTest testRestore
    runFunctionalTest cleanup
fi

endTests

