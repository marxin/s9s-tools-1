#! /bin/bash
MYNAME=$(basename $0)
MYBASENAME=$(basename $0 .sh)
MYDIR=$(dirname $0)
STDOUT_FILE=ft_errors_stdout
VERBOSE=""
VERSION="0.0.3"
LOG_OPTION="--wait"
CLUSTER_NAME="${MYBASENAME}_$$"
CLUSTER_ID=""
PIP_CONTAINER_CREATE=$(which "pip-container-create")
CONTAINER_SERVER=""

OPTION_LDAP_CONFIG_FILE="/etc/cmon-ldap.cnf"


cd $MYDIR
source ./include.sh
source ./include_ldap.sh

#
# Prints usage information and exits.
#
function printHelpAndExit()
{
cat << EOF
Usage: $MYNAME [OPTION]... [TESTNAME]
 
  $MYNAME - Testing for basic LDAP support.

  -h, --help       Print this help and exit.
  --verbose        Print more messages.
  --print-json     Print the JSON messages sent and received.
  --log            Print the logs while waiting for the job to be ended.
  --print-commands Do not print unit test info, print the executed commands.
  --reset-config   Remove and re-generate the ~/.s9s directory.
  --server=SERVER  Use the given server to create containers.
  --ldap-url

EOF
    exit 1
}

ARGS=$(\
    getopt -o h \
        -l "help,verbose,print-json,log,print-commands,reset-config,server:" \
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
            OPTION_VERBOSE="--verbose"
            ;;

        --log)
            shift
            LOG_OPTION="--log"
            ;;

        --print-json)
            shift
            OPTION_PRINT_JSON="--print-json"
            ;;

        --print-commands)
            shift
            DONT_PRINT_TEST_MESSAGES="true"
            PRINT_COMMANDS="true"
            ;;

        --reset-config)
            shift
            OPTION_RESET_CONFIG="true"
            ;;

        --server)
            shift
            CONTAINER_SERVER="$1"
            shift
            ;;

        --)
            shift
            break
            ;;
    esac
done


function ldap_config_ok()
{

    emit_ldap_config \
        --ldap-url "$LDAP_URL"

    return 0
}

function ldap_config_bad_url()
{
    emit_ldap_config \
        --ldap-url "ldap://nosuchserver.homelab.local:389"

    return 0
}

function testCreateLdapConfigOk()
{
    print_title "Creating the Cmon LDAP Configuration File"
    cat <<EOF
  This test will create and overwrite the '$OPTION_LDAP_CONFIG_FILE', a 
  configuration file that holds the settings of the LDAP settnings for the 
  Cmon Controller.
EOF
    
    begin_verbatim

    if [ -n "$LDAP_URL" ]; then
        success "  o LDAP URL is $LDAP_URL, OK."
    else
        failure "The LDAP_URL variable is empty."
    fi

    ldap_config_ok |\
        tee $OPTION_LDAP_CONFIG_FILE | \
        print_ini_file


    end_verbatim


}

function testCreateLdapConfigBadUrl()
{
    print_title "Creating the Cmon LDAP Configuration File"
    cat <<EOF
  This test will create and overwrite the '$OPTION_LDAP_CONFIG_FILE', a 
  configuration file that holds the settings of the LDAP settnings for the 
  Cmon Controller.
EOF
    
    begin_verbatim

    if [ -n "$LDAP_URL" ]; then
        success "  o LDAP URL is $LDAP_URL, OK."
    else
        failure "The LDAP_URL variable is empty."
    fi

    ldap_config_bad_url |\
        tee $OPTION_LDAP_CONFIG_FILE | \
        print_ini_file


    end_verbatim


}

function testCmonDbUser()
{
    print_title "Testing User with CmonDb Origin"

    begin_verbatim
    mys9s user --stat ${PROJECT_OWNER}

    check_user \
        --user-name    "${PROJECT_OWNER}"  \
        --cdt-path     "/" \
        --group        "testgroup" \
        --dn           "-" \
        --origin       "CmonDb"    

    end_verbatim
}

#
# Checking the successful authentication of an LDAP user with the user 
# "username".
#
function testLdapUser1()
{
    local username="username"

    print_title "Checking LDAP Authentication with user '$username'"

    cat <<EOF | paragraph
  This test checks the LDAP authentication using the simple name. The user
  should be able to authenticate.
EOF

    begin_verbatim

    mys9s user \
        --list \
        --long \
        --cmon-user="$username" \
        --password=p

    check_exit_code_no_job $?
   
    mys9s user \
        --stat \
        --long \
        --cmon-user="$username" \
        --password=p \
        username

    check_exit_code_no_job $?

    check_user \
        --user-name    "$username"  \
        --full-name    "firstname lastname" \
        --email        "username@domain.hu" \
        --cdt-path     "/" \
        --group        "ldapgroup" \
        --dn           "cn=username,dc=homelab,dc=local" \
        --origin       "LDAP"

    end_verbatim
}

function testLdapUser2()
{
    local username="${PROJECT_OWNER}1"

    print_title "LDAP Authentication with '$username'"
    cat <<EOF | paragraph
  This test checks the LDAP authentication using the simple name. This is 
  the first login of this user.
EOF

    begin_verbatim
    mys9s user \
        --list \
        --long \
        --cmon-user="$username" \
        --password=p

    check_exit_code_no_job $?
   
    mys9s user \
        --stat \
        --long \
        --cmon-user="$username" \
        --password=p \
        ${PROJECT_OWNER}1

    check_exit_code_no_job $?
    
    check_user \
        --user-name    "$username"  \
        --cdt-path     "/" \
        --group        "ldapgroup" \
        --dn           "cn=${PROJECT_OWNER}1,dc=homelab,dc=local" \
        --origin       "LDAP"

    end_verbatim
}


#
# Checking the successful authentication of an LDAP user.
#
function testLdapUserFail1()
{
    local username="username"

    print_title "Checking LDAP Authentication with user '$username'"

    cat <<EOF | paragraph
  This test checks the LDAP authentication using the simple name. The user
  should not be able to authenticate, because the Cmon Group is not created in
  advance.
EOF

    begin_verbatim
    #
    # Searching LDAP groups for user 'username'.
    # Considering cn=ldapgroup,dc=homelab,dc=local as group.
    # Group 'ldapgroup' was not found on Cmon.
    # No Cmon group assigned for user 'username'.
    #
    mys9s user \
        --list \
        --long \
        --cmon-user="$username" \
        --password=p

    if [ $? -eq 0 ]; then
        failure "The user should've failed to authenticate."
    else
        success "  o Command failed, ok."
    fi

    # FIXME: We should check that the user does not exist.
    end_verbatim
}

#
# Checking the successful authentication of an LDAP user.
#
function testLdapUserFail2()
{
    local username="${PROJECT_OWNER}1"

    print_title "Checking LDAP Authentication with user '$username'"

    cat <<EOF | paragraph
  This test checks the LDAP authentication using the simple name. The user
  should not be able to authenticate, because the Cmon Group is not created in
  advance.
EOF

    begin_verbatim
    #
    # Searching LDAP groups for user 'username'.
    # Considering cn=ldapgroup,dc=homelab,dc=local as group.
    # Group 'ldapgroup' was not found on Cmon.
    # No Cmon group assigned for user 'username'.
    #
    mys9s user \
        --list \
        --long \
        --cmon-user="$username" \
        --password=p

    if [ $? -eq 0 ]; then
        failure "The user should've failed to authenticate."
    else
        success "  o Command failed, ok."
    fi

    # FIXME: We should check that the user does not exist.
    end_verbatim
}

#
# Running the requested tests.
#
startTests
reset_config
grant_user --group "testgroup"

if [ "$1" ]; then
    for testName in $*; do
        runFunctionalTest "$testName"
    done
else
    runFunctionalTest testCmonDbUser
    runFunctionalTest testCreateLdapGroup
    runFunctionalTest testLdapSupport
    
    runFunctionalTest testCreateLdapConfigBadUrl
    runFunctionalTest testLdapUserFail1
    runFunctionalTest testLdapUserFail2
    
    runFunctionalTest testCreateLdapConfigOk
    runFunctionalTest testLdapUser1
    runFunctionalTest testLdapUser2

    #
    # FIXME: Here is a question: what should happen if now we remove the
    # mapping? The user is already created and so the authentication will
    # succeed.
    #
fi

endTests

