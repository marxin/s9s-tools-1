#! /bin/bash
MYNAME=$(basename $0)
MYBASENAME=$(basename $0 .sh)
MYDIR=$(dirname $0)
STDOUT_FILE=ft_errors_stdout
VERBOSE=""
LOG_OPTION="--wait"
CLUSTER_NAME="${MYBASENAME}_$$"
CLUSTER_ID=""
OPTION_INSTALL=""
PIP_CONTAINER_CREATE=$(which "pip-container-create")
CONTAINER_SERVER=""
DATABASE_USER="$USER"
PROVIDER_VERSION=$PERCONA_GALERA_DEFAULT_PROVIDER_VERSION

# The IP of the node we added first and last. Empty if we did not.
FIRST_ADDED_NODE=""

cd $MYDIR
source ./include.sh

#
# Prints usage information and exits.
#
function printHelpAndExit()
{
cat << EOF
Usage: 
  $MYNAME [OPTION]... [TESTNAME]
 
  $MYNAME - Test script for s9s to check backup in ndb clusters.

  -h, --help       Print this help and exit.
  --verbose        Print more messages.
  --log            Print the logs while waiting for the job to be ended.
  --server=SERVER  The name of the server that will hold the containers.
  --print-commands Do not print unit test info, print the executed commands.
  --install        Just install the cluster and exit.
  --reset-config   Remove and re-generate the ~/.s9s directory.
  --provider-version=STRING The SQL server provider version.

EXAMPLE
 ./ft_galera.sh --print-commands --server=storage01 --reset-config --install
EOF
    exit 1
}

ARGS=$(\
    getopt -o h \
        -l "help,verbose,log,server:,print-commands,install,reset-config,\
provider-version:" \
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

        --provider-version)
            shift
            PROVIDER_VERSION="$1"
            shift
            ;;

        --)
            shift
            break
            ;;
    esac
done

#
# This test will allocate a few nodes and install a new cluster.
#
function testCreateCluster()
{
    local nodes
    local nodeName

    print_title "Creating an NDB Cluster"
    begin_verbatim

    echo "Creating node #0"
    nodeName=$(create_node --autodestroy)
    nodes+="mysql://$nodeName;ndb_mgmd://$nodeName;"
    FIRST_ADDED_NODE="$nodeName"

    echo "Creating node #1"
    nodeName=$(create_node --autodestroy)
    nodes+="mysql://$nodeName;ndb_mgmd://$nodeName;"
    
    echo "Creating node #2"
    nodeName=$(create_node --autodestroy)
    nodes+="ndbd://$nodeName;"
    
    echo "Creating node #3"
    nodeName=$(create_node --autodestroy)
    nodes+="ndbd://$nodeName"

    #
    # Creating an NDB cluster.
    #
    mys9s cluster \
        --create \
        --cluster-type=ndb \
        --nodes="$nodes" \
        --vendor=oracle \
        --cluster-name="$CLUSTER_NAME" \
        --provider-version=$PROVIDER_VERSION \
        $LOG_OPTION

    check_exit_code $?

    CLUSTER_ID=$(find_cluster_id $CLUSTER_NAME)
    if [ "$CLUSTER_ID" -gt 0 ]; then
        success "Cluster ID is $CLUSTER_ID"
    else
        failure "Cluster ID '$CLUSTER_ID' is invalid"
    fi

    wait_for_cluster_started "$CLUSTER_NAME"
    end_verbatim
}

#
# Creating a new account on the cluster.
#
function testCreateAccount()
{
    local userName

    print_title "Testing account creation."
    begin_verbatim

    #
    # This command will create a new account on the cluster.
    #
    if [ -z "$CLUSTER_ID" ]; then
        failure "No cluster ID found."
        return 1
    fi

    mys9s account \
        --create \
        --cluster-id=$CLUSTER_ID \
        --account="$DATABASE_USER:password@1.2.3.4" \
        --with-database
    
    exitCode=$?
    if [ "$exitCode" -ne 0 ]; then
        failure "Exit code is not 0 while creating an account."
    fi

    mys9s account --list --cluster-id=1 "$DATABASE_USER"
    userName="$(s9s account --list --cluster-id=1 "$DATABASE_USER")"
    if [ "$userName" != "$DATABASE_USER" ]; then
        failure "Failed to create user '$DATABASE_USER'."
    fi

    end_verbatim
}

#
# Creating a new database on the cluster.
#
function testCreateDatabase()
{
    local userName

    print_title "Creating Database"
    begin_verbatim

    #
    # This command will create a new database on the cluster.
    #
    mys9s cluster \
        --create-database \
        --cluster-id=$CLUSTER_ID \
        --db-name="testCreateDatabase" 
    
    exitCode=$?
    printVerbose "exitCode = $exitCode"
    if [ "$exitCode" -ne 0 ]; then
        failure "Exit code is $exitCode while creating a database."
    fi

    mys9s cluster \
        --list-database \
        --long \
        --cluster-id=$CLUSTER_ID 

    #
    # This command will create a new account on the cluster and grant some
    # rights to the just created database.
    #
    mys9s account \
        --grant \
        --cluster-id=$CLUSTER_ID \
        --account="$DATABASE_USER" \
        --privileges="testCreateDatabase.*:DELETE" \
        --batch 
    
    exitCode=$?
    printVerbose "exitCode = $exitCode"
    if [ "$exitCode" -ne 0 ]; then
        failure "Exit code is $exitCode while granting privileges."
    fi

    mys9s account --list --cluster-id=1 --long "$DATABASE_USER"
    end_verbatim
}

#
# The first function that creates a backup.
#
function testCreateBackup01()
{
    local node
    local value

    print_title "Creating a Backup"
    begin_verbatim

    #
    # Creating the backup.
    #
    #    --to-individual-files \
    mys9s backup \
        --create \
        --title="Backup created by 'ft_backup_ndb.sh'" \
        --cluster-id=$CLUSTER_ID \
        --nodes=$FIRST_ADDED_NODE:3306 \
        --backup-dir=/tmp \
        --use-pigz \
        $LOG_OPTION
    
    check_exit_code $?

    #
    #
    #
    print_title "Checking the Properties of the Backup"
   
    mys9s backup --list --long
    #mys9s backup --list-databases --long
    #mys9s backup --list-files --long
    #mys9s backup --list --print-json

    value=$(s9s backup --list --backup-id=1 | wc -l)
    if [ "$value" != 1 ]; then
        failure "There should be 1 backup in the output."
    else
        success "  o There is 1 backup, ok."
    fi
    
    value=$(s9s backup --list --backup-id=1 --long --batch | awk '{print $6}')
    if [ "$value" != "COMPLETED" ]; then
        failure "The backup should be completed."
        return 1
    else
        success "  o The backup is completed, ok."
    fi

    value=$(s9s backup --list --backup-id=1 --long --batch | awk '{print $7}')
    if [ "$value" != "$USER" ]; then
        failure "The owner of the backup should be '$USER'"
    else
        success "  o The owner of the backup is $USER, ok."
    fi
    
    value=$(s9s backup --list --backup-id=1 --long --batch | awk '{print $3}')
    if [ "$value" != "1" ]; then
        failure "The cluster ID for the backup should be '1'."
    else
        success "  o The cluster ID of the backup 1, ok."
    fi

    # Checking the path.
    value=$(\
        s9s backup --list-files --full-path --backup-id=1 | \
        grep '^/tmp/BACKUP-1/' | \
        wc -l)

    if [ "$value" -lt 2 ]; then
        failure "Two files should be listed in '/tmp/BACKUP-1/'"
        mys9s backup --list-files --full-path --backup-id=1
    else
        success "  o There are at least two files, ok"
    fi

    end_verbatim
}

#
# Running the requested tests.
#
startTests
rm -rvf /tmp/BACKUP-1

reset_config
grant_user

if [ "$OPTION_INSTALL" ]; then
    runFunctionalTest testCreateCluster
elif [ "$1" ]; then
    for testName in $*; do
        runFunctionalTest "$testName"
    done
else
    runFunctionalTest testCreateCluster
    runFunctionalTest testCreateAccount
    #runFunctionalTest testCreateDatabase
    runFunctionalTest testCreateBackup01
fi

endTests


