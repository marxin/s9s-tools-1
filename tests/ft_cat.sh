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
PROVIDER_VERSION="5.7"

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
 
  $MYNAME - Test script for s9s to check Galera clusters.

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

#CLUSTER_ID=$($S9S cluster --list --long --batch | awk '{print $1}')

if [ -z $(which pip-container-create) ]; then
    printError "The 'pip-container-create' program is not found."
    printError "Don't know how to create nodes, giving up."
    exit 1
fi


function checkTreeAccess()
{
    local retcode
    local files
    local file

    print_title "Checking Access Rights"

    begin_verbatim
    mys9s tree --tree --all
    mys9s tree --list --long --all --recursive --full-path

    #
    # Checking the access rights of a normal user.
    #
    if ! s9s tree --access --batch --privileges="rwx" /; then
        failure "The user has no access to '/'."
    fi
    
    if ! s9s tree --access --batch --privileges="r" /groups; then
        failure "The user has no access to '/groups'."
    fi
    
    if   s9s tree --access --batch --privileges="rwx" /groups; then
        failure "The user has write access to '/groups'."
    fi

    files+="/.runtime/cluster_manager"
    files+=" /.runtime/host_manager"
    files+=" /.runtime/jobs/job_manager"
    files+=" /.runtime/mutexes"
    files+=" /.runtime/server_manager"
    files+=" /.runtime/threads"
    files+=" /.runtime/user_manager"

    #
    # Normal user should not have access to some special files.
    #
    for file in $files; do
        s9s tree \
            --access \
            --privileges="r" \
            "$file" \
            >/dev/null 2>/dev/null

        retcode=$?
        if [ "$retcode" -eq 0 ]; then
            failure "Normal user should not have access to '$file'."
            exit 1
        fi
    done

    #
    # Checking if the system user has access to some special files.
    #
    for file in $files; do
        s9s tree \
            --access \
            --privileges="r" \
            --cmon-user=system \
            --password=secret \
            "$file" 
    
        retcode=$?
        if [ "$retcode" -ne 0 ]; then
            failure "The system user should have access to '$file'."
            exit 1
        fi
    done

    end_verbatim
}

function checkList()
{
    local old_ifs="$IFS"
    local n_object_found=0
    local line
    local name
    local mode
    local owner
    local group

    #
    #
    #
    print_title "Checking Tree List"
    
    begin_verbatim
    IFS=$'\n'
    for line in $(s9s tree --list --long --all --recursive --full-path --batch)
    do
        line=$(echo "$line" | sed 's/[0-9]*, [0-9]*/   -/g')
        line=$(echo "$line" | sed 's/  / /g')
        line=$(echo "$line" | sed 's/  / /g')
        line=$(echo "$line" | sed 's/  / /g')

        name=$(echo "$line" | awk '{print $5}')
        mode=$(echo "$line" | awk '{print $1}')
        owner=$(echo "$line" | awk '{print $3}')
        group=$(echo "$line" | awk '{print $4}')
        
        echo "  checking line: $line"
        case "$name" in
            /.runtime)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "drwxrwxr--" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/cluster_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/host_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/jobs/job_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/mutexes)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/process_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/server_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/threads)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.runtime/user_manager)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-r--------" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
            
            /.issue)
                [ "$owner" != "system" ] && failure "Owner is '$owner'."
                [ "$group" != "admins" ] && failure "Group is '$group'."
                [ "$mode"  != "-rw-r--r--" ] && failure "Mode is '$mode'."
                let n_object_found+=1
                ;;
        esac
    done
    IFS=$old_ifs 

    echo "n_object_found: $n_object_found"
    if [ "$n_object_found" -lt 10 ]; then
        failure "Some special files were not found."
    else
        success "All special files were found."
    fi

    end_verbatim
}

function testClusterManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/cluster_manager"

    print_title "Checking $file"
    begin_verbatim

    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    end_verbatim
}

function testHostManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/host_manager"

    print_title "Checking $file"

    begin_verbatim
    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    end_verbatim
}

function testJobManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/job_manager"

    print_title "Checking $file"

    begin_verbatim
    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    end_verbatim
}

function testProcessManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/process_manager"

    print_title "Checking $file"

    begin_verbatim
    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    end_verbatim
}

function testServerManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/server_manager"

    print_title "Checking $file"

    begin_verbatim
    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    end_verbatim
}

function testUserManager()
{
    local old_ifs="$IFS"
    local file="/.runtime/user_manager"
    local n_names_found=0

    print_title "Checking $file"

    begin_verbatim
    mys9s tree \
        --cat \
        --cmon-user=system \
        --password=secret \
        $file

    #
    # Checking the format of the file and the data.
    #
    IFS=$'\n'
    for line in $(s9s tree --cat --cmon-user=system --password=secret $file)
    do
        name=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $3}')
        #printf "%32s is %s\n" "$name" "$value"
        case "$name" in 
            user_manager_instance)
                [ -z "$value" ] && failure "Value is empty for $name."
                let n_names_found+=1
                ;;
        esac
                
        [ -z "$name" ]  && failure "Name is empty."
        [ -z "$value" ] && failure "Value is empty for $name."
    done 

    echo "  n_names_found: $n_names_found"
    end_verbatim
}

#
# Running the requested tests.
#
startTests

reset_config
grant_user

if [ "$OPTION_INSTALL" ]; then
    runFunctionalTest testCreateCluster
elif [ "$1" ]; then
    for testName in $*; do
        runFunctionalTest "$testName"
    done
else
    runFunctionalTest checkTreeAccess
    runFunctionalTest checkList
    runFunctionalTest testClusterManager
    runFunctionalTest testHostManager
    runFunctionalTest testJobManager
    runFunctionalTest testProcessManager
    runFunctionalTest testServerManager
    runFunctionalTest testUserManager
fi

endTests


