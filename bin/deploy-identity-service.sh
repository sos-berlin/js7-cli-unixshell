#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2024-08-24
# Purpose:  Status Operations on JOC Cockpit
# ------------------------------------------------------------
#
# Examples, see https://kb.sos-berlin.com/x/-YZvCQ

# request_options=(--url=http://localhost:4446 --user=root --password=root)  
#
# check license
# ./deploy-identity-service.sh get-account "${request_options[@]}" --service=JOC-INITIAL
#

# ------------------------------
# Global script variables
# ------------------------------

script_home=$(dirname "$(cd "$(dirname "$0")" >/dev/null && pwd)")

joc_url=
joc_user=
joc_password=
joc_cacert=
joc_client_cert=
joc_client_key=
timeout=60
make_dirs=
show_logs=
log_dir=
log_dir=
verbose=0
action=

item=
start_time=$(date +"%Y-%m-%dT%H-%M-%S")
response_json=
access_token=

controller_id=
account=
new_account=
account_password=
new_password=
comment=

service=
service_type=
ordering=0
new_service=
second_service=
authentication_scheme=
settings=

role=
new_role=

permission=
new_permission=

folder=
new_folder=

force_password_change=false
enabled=false
disabled=false
blocked=false
excluded=false
required=false
recursive=false

audit_message=
audit_time_spent=0
audit_link=

# ------------------------------
# Inline Functions
# ------------------------------

AskPassword() {
    joc_password="$(
        exec < /dev/tty || exit
        tty_config=$(stty -g) || exit
        trap 'stty "$tty_config"' EXIT INT TERM
        stty -echo || exit
        printf 'Password: ' > /dev/tty
        IFS= read -r joc_password; rc=$? 2> /dev/tty
        echo > /dev/tty
        printf '%s\n' "${joc_password}"
        exit "$rc"
    )"
}

AskAccountPassword() {
    account_password="$(
        exec < /dev/tty || exit
        tty_config=$(stty -g) || exit
        trap 'stty "$tty_config"' EXIT INT TERM
        stty -echo || exit
        printf 'Account Password: ' > /dev/tty
        IFS= read -r account_password; rc=$? 2> /dev/tty
        echo > /dev/tty
        printf '%s\n' "${account_password}"
        exit "$rc"
    )"
}

AskNewPassword() {
    new_password="$(
        exec < /dev/tty || exit
        tty_config=$(stty -g) || exit
        trap 'stty "$tty_config"' EXIT INT TERM
        stty -echo || exit
        printf 'New Password: ' > /dev/tty
        IFS= read -r new_password; rc=$? 2> /dev/tty
        echo > /dev/tty
        printf '%s\n' "${new_password}"
        exit "$rc"
    )"
}

Log()
{
    if [ -n "${log_file}" ] && [ -f "${log_file}" ]
    then
        echo "$@" >> "${log_file}"
    fi
    
    if [ -z "${show_logs}" ]
    then
        echo "$@"
    fi
}

LogVerbose()
{
    if [ "${verbose}" -gt 0 ]
    then
        if [ -n "${log_file}" ] && [ -f "${log_file}" ]
        then
            echo "$@" >> "${log_file}"
        fi
    
        if [ -z "${show_logs}" ]
        then
            >&2 echo "$@"
        fi
    fi
}

LogWarning()
{
    if [ -n "${log_file}" ] && [ -f "${log_file}" ]
    then
        echo "[WARN]" "$@" >> "${log_file}"
    fi
    
    >&2 echo "[WARN]" "$@"
}

LogError()
{
    if [ -n "${log_file}" ] && [ -f "${log_file}" ]
    then
        echo "[ERROR]" "$@" >> "${log_file}"
    fi
    
    >&2 echo "[ERROR]" "$@"
}

Curl_Options()
{ 
    LogVerbose ".... Curl_Options"
    curl_options=(-k -L -s -S -X POST -m "${timeout}")

    if [ "${joc_cacert}" != "" ]
    then
        curl_options+=(--cacert "${joc_cacert}")
    fi

    if [ "${joc_client_cert}" != "" ]
    then
        curl_options+=(--cert "${joc_client_cert}")
    fi

    if [ "${joc_client_key}" != "" ]
    then
        curl_options+=(--key "${joc_client_key}")
    fi

    if [ "${verbose}" -gt 1 ]
    then
        curl_options+=(--verbose)
    fi

    curl_log_options=("${curl_options[@]}")

    if [ -n "${joc_user}" ] && [ -n "${joc_password}" ]
    then
        curl_options+=(--user "${joc_user}":"${joc_password}")
        curl_log_options+=(--user "${joc_user}:********")
    fi
}

Audit_Log_Request()
{
    if [ -n "${audit_message}" ]
    then
        request_body="${request_body}, \"auditLog\": { \"comment\": \"${audit_message}\""

        if [ "${audit_time_spent}" -gt 0 ]
        then
            request_body="${request_body}, \"timeSpent\": ${audit_time_spent}"
        fi

        if [ -n "${audit_link}" ]
        then
            request_body="${request_body}, \"ticketLink\": \"${audit_link}\""
        fi

        request_body="${request_body} }"
    fi
}

Login()
{ 
    LogVerbose ".. Login"
    Curl_Options

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H "Accept: application/json" -H "Content-Type: application/json" ${joc_url}/joc/api/authentication/login"
    response_json=$(curl "${curl_options[@]}" -H "Accept: application/json" -H "Content-Type: application/json" "${joc_url}"/joc/api/authentication/login)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        access_token=$(echo "${response_json}" | jq -r '.accessToken // empty' | sed 's/^"//' | sed 's/"$//')
        LogVerbose ".... access token: ${access_token}"
        if [ -z "${access_token}" ]
        then
            LogError "Login failed: ${response_json}"
            exit 4
        fi
    else
        LogError "Login failed: ${response_json}"
        exit 4
    fi
}

Logout()
{
    LogVerbose ".. Logout"
    Curl_Options

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" ${joc_url}/joc/api/authentication/logout"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" "${joc_url}"/joc/api/authentication/logout)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        item=$(echo "${response_json}" | jq -r 'select(.isAuthenticated == false) // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${item}" ]
        then
            LogError "Logout failed: ${response_json}"
            exit 4
        fi
        access_token=
    else
        LogError "Logout failed: ${response_json}"
        exit 4
    fi
}

Get_Account()
{
    LogVerbose ".. Get_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"enabled\": ${enabled}, \"disabled\": ${disabled}"

    if [ -n "${account}" ]
    then
        request_body="${request_body}, \"accountName\": \"${account}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/accounts"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/accounts)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.accountItems // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Account() failed: ${response_json}"
        exit 4
    fi
    
    echo "${response_json}" | jq -r '.accountItems // empty'
}

Get_Blocked_Account()
{
    LogVerbose ".. Get_Blocked_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    if [ -n "${account}" ]
    then
        request_body="${request_body}, \"accountName\": \"${account}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/blockedAccounts"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/blockedAccounts)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.blockedAccounts // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Blocked_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Blocked_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Blocked_Account() failed: ${response_json}"
        exit 4
    fi
    
    echo "${response_json}" | jq -r '.blockedAccounts // empty'
}

Store_Account()
{
    LogVerbose ".. Store_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"accountName\": \"${account}\", \"disabled\": ${disabled}, \"forcePasswordChange\": ${force_password_change}"

    if [ -n "${account_password}" ]
    then
        request_body="${request_body}, \"password\": \"${account_password}\""
    fi

    request_body="${request_body}, \"roles\": ["
    comma=
    set -- "$(echo "${role}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/account/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/account/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Store_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Store_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Account() failed: ${response_json}"
        exit 4
    fi
}

Rename_Account()
{
    LogVerbose ".. Rename_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"accountOldName\": \"${account}\", \"accountNewName\": \"${new_account}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/account/rename"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/account/rename)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Rename_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Rename_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Rename_Account() failed: ${response_json}"
        exit 4
    fi
}

Remove_Account()
{
    LogVerbose ".. Remove_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"enabled\": ${enabled}, \"disabled\": ${disabled}"

    request_body="${request_body}, \"accountNames\": ["
    comma=
    set -- "$(echo "${account}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/accounts/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/accounts/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Remove_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Remove_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Account() failed: ${response_json}"
        exit 4
    fi
}

Get_Account_Permission()
{
    LogVerbose ".. Get_Account_Permission()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"accountName\": \"${account}\""

    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/account/permissions"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/account/permissions)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.roles // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Account_Permission() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Account_Permission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Account_Permission() failed: ${response_json}"
        exit 4
    fi
    
    echo "${response_json}" | jq -r '.roles // empty'
}

Set_Account_Password()
{
    LogVerbose ".. Set_Account_Password()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"accountName\": \"${account}\", \"oldPassword\": \"${account_password}\", \"password\": \"${new_password}\", \"repeatedPassword\": \"${new_password}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/account/changepassword"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/account/changepassword)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Set_Account_Password() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Set_Account_Password() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Set_Account_Password() failed: ${response_json}"
        exit 4
    fi
}

Reset_Account_Password()
{
    LogVerbose ".. Reset_Account_Password()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    request_body="${request_body}, \"accountNames\": ["
    comma=
    set -- "$(echo "${account}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/accounts/resetpassword"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/accounts/resetpassword)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Reset_Account_Password() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Reset_Account_Password() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Reset_Account_Password() failed: ${response_json}"
        exit 4
    fi
}

Enable_Account()
{
    LogVerbose ".. Enable_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    request_body="${request_body}, \"accountNames\": ["
    comma=
    set -- "$(echo "${account}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/accounts/enable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/accounts/enable)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Enable_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Enable_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Enable_Account() failed: ${response_json}"
        exit 4
    fi
}

Disable_Account()
{
    LogVerbose ".. Disable_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    request_body="${request_body}, \"accountNames\": ["
    comma=
    set -- "$(echo "${account}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/accounts/disable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/accounts/disable)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Disable_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Disable_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Disable_Account() failed: ${response_json}"
        exit 4
    fi
}

Block_Account()
{
    LogVerbose ".. Block_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"accountName\": \"${account}\""

    if [ -n "${comment}" ]
    then
        request_body="${request_body}, \"comment\": \"${comment}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/blockedAccount/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/blockedAccount/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Block_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Block_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Block_Account() failed: ${response_json}"
        exit 4
    fi
}

Unblock_Account()
{
    LogVerbose ".. Unblock_Account()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    request_body="${request_body}, \"accountNames\": ["
    comma=
    set -- "$(echo "${account}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/blockedAccounts/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/blockedAccounts/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Unblock_Account() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Unblock_Account() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Unblock_Account() failed: ${response_json}"
        exit 4
    fi
}

Get_Role()
{
    LogVerbose ".. Get_Role()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    if [ -n "${role}" ]
    then
        request_body="${request_body}, \"roleName\": \"${role}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"

    if [ -n "${role}" ]
    then
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/role"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/role)
    else
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/roles"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/roles)
    fi

    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        if [ -n "${role}" ]
        then
            ok=$(echo "${response_json}" | jq -r '.roleName // empty' | sed 's/^"//' | sed 's/"$//')
        else
            ok=$(echo "${response_json}" | jq -r '.roles // empty' | sed 's/^"//' | sed 's/"$//')
        fi
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Role() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Role() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Role() failed: ${response_json}"
        exit 4
    fi

    if [ -n "${role}" ]
    then
        echo "${response_json}" | jq -r '.accountItems // empty'
    else
        echo "${response_json}" | jq -r '.roles // empty'
    fi
}

Store_Role()
{
    LogVerbose ".. Store_Role()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\""

    if [ "${ordering}" -gt 0 ]
    then
        request_body="${request_body}, \"ordering\": ${ordering}"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/role/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/role/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Store_Role() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Store_Role() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Role() failed: ${response_json}"
        exit 4
    fi
}

Rename_Role()
{
    LogVerbose ".. Rename_Role()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleOldName\": \"${role}\", \"roleNewName\": \"${new_role}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/role/rename"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/role/rename)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Rename_Role() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Rename_Role() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Rename_Role() failed: ${response_json}"
        exit 4
    fi
}

Remove_Role()
{
    LogVerbose ".. Remove_Role()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""

    request_body="${request_body}, \"roleNames\": ["
    comma=
    set -- "$(echo "${role}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/roles/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/roles/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Remove_Role() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Remove_Role() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Role() failed: ${response_json}"
        exit 4
    fi
}

Get_Permission()
{
    LogVerbose ".. Get_Permission()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\""

    if [ -n "${permission}" ]
    then
        request_body="${request_body}, \"permissionPath\": \"${permission}\""
    fi

    if [ -n "${controller_id}" ]
    then
        request_body="${request_body}, \"controllerId\": \"${controller_id}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"

    if [ -n "${permission}" ]
    then
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/permission"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/permission)
    else
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/permissions"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/permissions)
    fi

    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        if [ -n "${permission}" ]
        then
            ok=$(echo "${response_json}" | jq -r '.permission // empty' | sed 's/^"//' | sed 's/"$//')
        else
            ok=$(echo "${response_json}" | jq -r '.permissions // empty' | sed 's/^"//' | sed 's/"$//')
        fi

        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Permission() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Permission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Permission() failed: ${response_json}"
        exit 4
    fi
    
    if [ -n "${permission}" ]
    then
        echo "${response_json}" | jq -r '. // empty'
    else
        echo "${response_json}" | jq -r '.permissions // empty'
    fi
}

Set_Permission()
{
    LogVerbose ".. Set_Permission()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\""

    request_body="${request_body}, \"permissions\": ["
    comma=
    set -- "$(echo "${permission}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} { \"permissionPath\": \"${i}\", \"excluded\": ${excluded} }"
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/permissions/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/permissions/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Set_Permission() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Set_Permission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Set_Permission() failed: ${response_json}"
        exit 4
    fi
}

Rename_Permission()
{
    LogVerbose ".. Rename_Permission()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"oldPermissionPath\": \"${permission}\", \"newPermission\": { \"permissionPath\": \"${new_permission}\", \"excluded\": ${excluded} }, \"controllerId\": \"${controller_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/permission/rename"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/permission/rename)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Rename_Permission() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Rename_Permission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Rename_Permission() failed: ${response_json}"
        exit 4
    fi
}

Remove_Permission()
{
    LogVerbose ".. Remove_Permission()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\""

    request_body="${request_body}, \"permissionPaths\": ["
    comma=
    set -- "$(echo "${permission}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/permissions/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/permissions/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Remove_Permission() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Remove_Permission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Permission() failed: ${response_json}"
        exit 4
    fi
}

Get_Folder_Permisions()
{
    LogVerbose ".. Get_Folder_Permisions()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\""

    if [ -n "${folder}" ]
    then
        request_body="${request_body}, \"folderName\": \"${folder}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"

    if [ -n "${folder}" ]
    then
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/folder"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/folder)
    else
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/folders"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/folders)
    fi

    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        if [ -n "${folder}" ]
        then
            ok=$(echo "${response_json}" | jq -r '.folder // empty' | sed 's/^"//' | sed 's/"$//')
        else
            ok=$(echo "${response_json}" | jq -r '.folders // empty' | sed 's/^"//' | sed 's/"$//')
        fi
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Folder_Permisions() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Folder_Permisions() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Folder_Permisions() failed: ${response_json}"
        exit 4
    fi

    if [ -n "${folder}" ]
    then
        echo "${response_json}" | jq -r '.folder // empty'
    else
        echo "${response_json}" | jq -r '.folders // empty'
    fi
}

Set_Folder_Permisions()
{
    LogVerbose ".. Set_Folder_Permisions()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\""

    request_body="${request_body}, \"folders\": ["
    comma=
    set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} { \"folder\": \"${i}\", \"recursive\": ${recursive} }"
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/folders/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/folders/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Set_Folder_Permisions() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Set_Folder_Permisions() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Set_Folder_Permisions() failed: ${response_json}"
        exit 4
    fi
}

Rename_Folder_Permisions()
{
    LogVerbose ".. Rename_Folder_Permisions()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\", \"oldFolderName\": \"${folder}\", \"newFolder\": { \"folder\": \"${new_folder}\", \"recursive\": ${recursive} }"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/folder/rename"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/folder/rename)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Rename_Folder_Permisions() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Rename_Folder_Permisions() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Rename_Folder_Permisions() failed: ${response_json}"
        exit 4
    fi
}

Remove_Folder_Permisions()
{
    LogVerbose ".. Remove_Folder_Permisions()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"roleName\": \"${role}\", \"controllerId\": \"${controller_id}\""

    request_body="${request_body}, \"folderNames\": ["
    comma=
    set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/folders/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/folders/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Remove_Folder_Permisions() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Remove_Folder_Permisions() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Folder_Permisions() failed: ${response_json}"
        exit 4
    fi
}

Get_Identity_Service()
{
    LogVerbose ".. Get_Identity_Service()"
    Curl_Options

    request_body="{ "

    if [ -n "${service}" ]
    then
        request_body="${request_body} \"identityServiceName\": \"${service}\""
    fi

    request_body="${request_body} }"

    LogVerbose ".... request:"

    if [ -n "${service}" ]
    then
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/identityservice"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/identityservice)
    else
        LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/identityservices"
        response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/identityservices)
    fi

    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        if [ -n "${service}" ]
        then
            ok=$(echo "${response_json}" | jq -r '.identityServiceName // empty' | sed 's/^"//' | sed 's/"$//')
        else
            ok=$(echo "${response_json}" | jq -r '.identityServiceItems // empty' | sed 's/^"//' | sed 's/"$//')
        fi
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Identity_Service() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Identity_Service() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Identity_Service() failed: ${response_json}"
        exit 4
    fi

    if [ -n "${service}" ]
    then
        echo "${response_json}" | jq -r '. // empty'
    else
        echo "${response_json}" | jq -r '.identityServiceItems // empty'
    fi
}

Store_Identity_Service()
{
    LogVerbose ".. Store_Identity_Service()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\", \"identityServiceType\": \"${service_type}\", \"disabled\": ${disabled}, \"required\": ${required}"

    if [ -n "${authentication_scheme}" ]
    then
        request_body="${request_body}, \"serviceAuthenticationScheme\": \"${authentication_scheme}\""
    fi

    if [ -n "${second_service}" ]
    then
        request_body="${request_body}, \"secondFactorIdentityServiceName\": \"${second_service}\""
    fi

    if [ "${ordering}" -gt 0 ]
    then
        request_body="${request_body}, \"ordering\": ${ordering}"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/identityservice/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/identityservice/store)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.identityServiceName // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Store_Identity_Service() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Store_Identity_Service() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Identity_Service() failed: ${response_json}"
        exit 4
    fi
}

Rename_Identity_Service()
{
    LogVerbose ".. Rename_Identity_Service()"
    Curl_Options

    request_body="{ \"identityServiceOldName\": \"${service}\", \"identityServiceNewName\": \"${new_service}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/identityservice/rename"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/identityservice/rename)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '."identityServiceNewName" // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Rename_Identity_Service() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Rename_Identity_Service() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Rename_Identity_Service() failed: ${response_json}"
        exit 4
    fi
}

Remove_Identity_Service()
{
    LogVerbose ".. Remove_Identity_Service()"
    Curl_Options

    request_body="{ \"identityServiceName\": \"${service}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/iam/identityservice/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/iam/identityservice/delete)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Remove_Identity_Service() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Remove_Identity_Service() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Identity_Service() failed: ${response_json}"
        exit 4
    fi
}

Get_Identity_Service_Settings()
{
    LogVerbose ".. Get_Identity_Service_Settings()"
    Curl_Options

    request_body="{ \"id\": 0, \"configurationType\": \"IAM\", \"name\": \"${service}\", \"objectType\": \"${service_type}\" }"

    LogVerbose ".... request:"

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/configuration"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/configuration)

    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.configuration // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Identity_Service_Settings() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Get_Identity_Service_Settings() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Identity_Service_Settings() failed: ${response_json}"
        exit 4
    fi

    echo "${response_json}" | jq -r '.configuration.configurationItem // empty'
}

Store_Identity_Service_Settings()
{
    LogVerbose ".. Store_Identity_Service_Settings()"
    Curl_Options

    ok=$(echo "$settings" | jq -r 'select(.simple) // empty')

    if [ -n "$ok" ]
    then
        request_body="{ \"id\": 0, \"name\": \"${service}\", \"objectType\": \"${service_type}\", \"configurationType\": \"IAM\", \"configurationItem\": $(echo "{ \"$(echo ${service_type} | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')\": ${settings} }" | jq -c | jq -RM)"
    else
        request_body="{ \"id\": 0, \"name\": \"${service}\", \"objectType\": \"${service_type}\", \"configurationType\": \"IAM\", \"configurationItem\": $(echo "${settings}" | jq -c | jq -RM)"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/configuration/save"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/configuration/save)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.id // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Store_Identity_Service_Settings() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Store_Identity_Service_Settings() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Identity_Service_Settings() failed: ${response_json}"
        exit 4
    fi
}

Usage()
{
    >&"$1" echo ""
    >&"$1" echo "Usage: $(basename "$0") [Command] [Options] [Switches]"
    >&"$1" echo ""
    >&"$1" echo "  Commands:"
    >&"$1" echo "    get-account             --service [--account] [--enabled] [--disabled] [--blocked]"
    >&"$1" echo "    store-account           --service  --account  [--role] [--disabled] [--account-password] [--force-password-change]"
    >&"$1" echo "    rename-account          --service  --account   --new-account"
    >&"$1" echo "    remove-account          --service  --account  [--enabled] [--disabled]"
    >&"$1" echo "    get-account-permission  --service  --account"
    >&"$1" echo "    set-account-password    --service  --account   --account-password --new-account-password"
    >&"$1" echo "    reset-account-password  --service  --account"
    >&"$1" echo "    enable-account          --service  --account"
    >&"$1" echo "    disable-account         --service  --account"
    >&"$1" echo "    block-account           --service  --account [--comment]"
    >&"$1" echo "    unblock-account         --service  --account"
    >&"$1" echo ""
    >&"$1" echo "    get-role                --service [--role]"
    >&"$1" echo "    store-role              --service  --role [--ordering]"
    >&"$1" echo "    rename-role             --service  --role  --new-role"
    >&"$1" echo "    remove-role             --service  --role"
    >&"$1" echo ""
    >&"$1" echo "    get-permission          --service  --role [--controller-id]"
    >&"$1" echo "    set-permission          --service  --role  --permission [--excluded] [--controller-id]"
    >&"$1" echo "    rename-permission       --service  --role  --permission  --new-permission [--excluded] [--controller-id]"
    >&"$1" echo "    remove-permission       --service  --role  --permission [--controller-id]"
    >&"$1" echo ""
    >&"$1" echo "    get-folder              --service  --role [--folder] [--controller-id]"
    >&"$1" echo "    set-folder              --service  --role  --folder  [--recursive] [--controller-id]"
    >&"$1" echo "    rename-folder           --service  --role  --folder   --new-folder [--recursive] [--controller-id]"
    >&"$1" echo "    remove-folder           --service  --role  --folder  [--controller-id]"
    >&"$1" echo ""
    >&"$1" echo "    get-service            [--service]"
    >&"$1" echo "    store-service           --service --service-type [--ordering] [--required] [--disabled]"
    >&"$1" echo "                           [--authentication-scheme] [--second-service]"
    >&"$1" echo "    rename-service          --service --new-service"
    >&"$1" echo "    remove-service          --service"
    >&"$1" echo "    get-service-settings    --service --service-type"
    >&"$1" echo "    store-service-settings  --service --service-type --settings"
    >&"$1" echo ""
    >&"$1" echo "  Options:"
    >&"$1" echo "    --url=<url>                        | required: JOC Cockpit URL"
    >&"$1" echo "    --user=<account>                   | required: JOC Cockpit user account"
    >&"$1" echo "    --password=<password>              | optional: JOC Cockpit password"
    >&"$1" echo "    --ca-cert=<path>                   | optional: path to CA Certificate used for JOC Cockpit login"
    >&"$1" echo "    --client-cert=<path>               | optional: path to Client Certificate used for login"
    >&"$1" echo "    --client-key=<path>                | optional: path to Client Key used for login"
    >&"$1" echo "    --timeout=<seconds>                | optional: timeout for request, default: ${timeout}"
    >&"$1" echo "    --controller-id=<id>               | optional: Controller ID"
    >&"$1" echo "    --account=<name[,name]>            | optional: list of accounts"
    >&"$1" echo "    --new-account=<name[,name]>        | optional: new account names"
    >&"$1" echo "    --account-password=<password>      | optional: password for account"
    >&"$1" echo "    --new-password=<password>          | optional: new password for account"
    >&"$1" echo "    --comment=<string>                 | optional: comment to blocked account"
    >&"$1" echo "    --service=<name>                   | required: Identity Service name"
    >&"$1" echo "    --service-type=<id>                | optional: Identity Service type such as JOC, LDAP, LDAP-JOC, OIDC, OIDC-JOC"
    >&"$1" echo "    --ordering=<number>                | optional: ordering of Identity Service or role by ascending number"
    >&"$1" echo "    --new-service=<name>               | optional: new Identity Service name"
    >&"$1" echo "    --second-service=<name>            | optional: second Identity Service for MFA"
    >&"$1" echo "    --authentication-scheme=<factor>   | optional: Identity Service authentication scheme: SINGLE-FACTOR, TWO-FACTOR"
    >&"$1" echo "    --settings=<json>                  | optional: Identity Service settings in JSON format"
    >&"$1" echo "    --role=<name[,name]>               | optional: list of roles"
    >&"$1" echo "    --new-role=<name>                  | optional: new role name"
    >&"$1" echo "    --permission=<id[,id]>             | optional: list of permission identifiers assigned a role"
    >&"$1" echo "    --new-permission=<id>              | optional: new permission identifier assigned a role"
    >&"$1" echo "    --folder=<name[,name]>             | optional: list of folders assigned a role"
    >&"$1" echo "    --new-folder=<name>                | optional: new folder assigned a role"
    >&"$1" echo "    --audit-message=<string>           | optional: audit log message"
    >&"$1" echo "    --audit-time-spent=<number>        | optional: audit log time spent in minutes"
    >&"$1" echo "    --audit-link=<url>                 | optional: audit log link"
    >&"$1" echo "    --log-dir=<directory>              | optional: path to directory holding the script's log files"
    >&"$1" echo ""
    >&"$1" echo "  Switches:"
    >&"$1" echo "    -h | --help                        | displays usage"
    >&"$1" echo "    -v | --verbose                     | displays verbose output, repeat to increase verbosity"
    >&"$1" echo "    -p | --password                    | asks for password"
    >&"$1" echo "    -a | --account-password            | asks for account password"
    >&"$1" echo "    -n | --new-password                | asks for new account password"
    >&"$1" echo "    -f | --force-password-change       | enforces password change on next login"
    >&"$1" echo "    -e | --enabled                     | filters for enabled accounts"
    >&"$1" echo "    -d | --disabled                    | filters for disabled accounts or disables Identity Services"
    >&"$1" echo "    -b | --blocked                     | filters for blocked accounts"
    >&"$1" echo "    -x | --excluded                    | sets excluded permissions"
    >&"$1" echo "    -q | --required                    | enforces use of Identity Service"
    >&"$1" echo "    -r | --recursive                   | applies folder operation to sub-folders"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/lwTWCQ"
    >&"$1" echo ""
}

Arguments()
{
    args="$*"

    if [ -z "$1" ]
    then
        Usage 1
        exit
    fi

    case "$1" in
        get-account|store-account|rename-account|remove-account|get-account-permission|set-account-password|reset-account-password|enable-account|disable-account|block-account|unblock-account|get-role|store-role|rename-role|remove-role|get-permission|set-permission|rename-permission|remove-permission|get-folder|set-folder|rename-folder|remove-folder|get-service|store-service|rename-service|remove-service|get-service-settings|store-service-settings) action=$1
                                    ;;
        -h|--help)                  Usage 1
                                    exit
                                    ;;
        *)                          Usage 2
                                    >&2 echo "unknown command: $1"
                                    exit 1
                                    ;;
    esac

    for option in "$@"
    do
        case "${option}" in
            --url=*)                joc_url=$(echo "${option}" | sed 's/--url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user=*)               joc_user=$(echo "${option}" | sed 's/--user=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --password=*)           joc_password=$(echo "${option}" | sed 's/--password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --ca-cert=*)            joc_cacert=$(echo "${option}" | sed 's/--ca-cert=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --client-cert=*)        joc_client_cert=$(echo "${option}" | sed 's/--client-cert=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --client-key=*)         joc_client_key=$(echo "${option}" | sed 's/--client-key=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --timeout=*)            timeout=$(echo "${option}" | sed 's/--timeout=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --controller-id=*)      controller_id=$(echo "${option}" | sed 's/--controller-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --account=*)            account=$(echo "${option}" | sed 's/--account=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-account=*)        new_account=$(echo "${option}" | sed 's/--new-account=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --account-password=*)   account_password=$(echo "${option}" | sed 's/--account-password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-password=*)       new_password=$(echo "${option}" | sed 's/--new-password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --comment=*)            comment=$(echo "${option}" | sed 's/--comment=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --service=*)            service=$(echo "${option}" | sed 's/--service=//')
                                    ;;
            --service-type=*)       service_type=$(echo "${option}" | sed 's/--service-type=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --ordering=*)           ordering=$(echo "${option}" | sed 's/--ordering=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-service=*)        new_service=$(echo "${option}" | sed 's/--new-service=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --second-service=*)     second_service=$(echo "${option}" | sed 's/--second-service=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --authentication-scheme=*)  authentication_scheme=$(echo "${option}" | sed 's/--authentication-scheme=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --settings=*)           settings=$(echo "${option}" | sed 's/--settings=//')
                                    ;;
            --role=*)               role=$(echo "${option}" | sed 's/--role=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-role=*)           new_role=$(echo "${option}" | sed 's/--new-role=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --permission=*)         permission=$(echo "${option}" | sed 's/--permission=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-permission=*)     new_permission=$(echo "${option}" | sed 's/--new-permission=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --folder=*)             folder=$(echo "${option}" | sed 's/--folder=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-folder=*)         new_folder=$(echo "${option}" | sed 's/--new-folder=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --audit-message=*)      audit_message=$(echo "${option}" | sed 's/--audit-message=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --audit-time-spent=*)   audit_time_spent=$(echo "${option}" | sed 's/--audit-time-spent=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --audit-link=*)         audit_link=$(echo "${option}" | sed 's/--audit-link=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --log-dir=*)            log_dir=$(echo "${option}" | sed 's/--log-dir=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            # Switches
            -h|--help)                      Usage 1
                                            exit
                                            ;;
            -v|--verbose)                   verbose=$((verbose + 1))
                                            ;;
            -p|--password)                  AskPassword
                                            ;;
            -a|--account-password)          AskAccountPassword
                                            ;;
            -n|--new-password)              AskNewPassword
                                            ;;
            -f|--force-password-change)     force_password_change=true
                                            ;;
            -e|--enabled)                   enabled=true
                                            ;;
            -d|--disabled)                  disabled=true
                                            ;;
            -b|--blocked)                   blocked=true
                                            ;;
            -x|--excluded)                  excluded=true
                                            ;;
            -q|--required)                  required=true
                                            ;;
            -r|--recursive)                 recursive=true
                                            ;;
            --make-dirs)                    make_dirs=1
                                            ;;
            --show-logs)                    show_logs=1
                                            ;;
                                            get-account|store-account|rename-account|remove-account|get-account-permission|set-account-password|reset-account-password|enable-account|disable-account|block-account|unblock-account|get-role|store-role|rename-role|remove-role|get-permission|set-permission|rename-permission|remove-permission|get-folder|set-folder|rename-folder|remove-folder|get-service|store-service|rename-service|remove-service|get-service-settings|store-service-settings) action=$1
                                            ;;
            *)                              Usage 2
                                            >&2 echo "unknown option: ${option}"
                                            exit 1
                                            ;;
        esac
    done


    if ! command -v curl &> /dev/null
    then
        LogError "curl utility not found"
        exit 1
    fi

    if ! command -v jq &> /dev/null
    then
        LogError "jq utility not found"
        exit 1
    fi

    if [ -n "${action}" ]
    then
        if [ -z "${joc_url}" ]
        then
            Usage 2
            LogError "JOC Cockpit URL not specified: --url=<url>"
            exit 1
        fi
    
        if [ -z "${joc_user}" ] && [ -z "${joc_client_key}" ]
        then
            Usage 2
            LogError "No JOC Cockpit client authentication certificate and no user account specified: --user=<account>"
            exit 1
        fi
    
        if [ -n "${joc_cacert}" ] && [ ! -f "${joc_cacert}" ]
        then
            Usage 2
            LogError "Root CA Certificate file not found: --cacert=${joc_cacert}"
            exit 1
        fi
    
        if [ -n "${joc_client_cert}" ] && [ ! -f "${joc_client_cert}" ]
        then
            LogError "Client Certificate file not found: --client-cert=${joc_client_cert}"
            Usage 2
            exit 1
        fi
    
        if [ -n "${joc_client_key}" ] && [ ! -f "${joc_client_key}" ]
        then
            Usage 2
            LogError "Client Private Key file not found: --client-key=${joc_client_key}"
            exit 1
        fi
    fi

    if [ ! "$action" = "get-service" ]
    then
        if [ -z "${service}" ]
        then
            Usage 2
            LogError "Identity Service must be specified: --service=<service>"
            exit 1
        fi
    fi

    actions="|store-account|rename-account|remove-account|get-account-permission|set-account-password|reset-account-password|)enable-account|disable-account|block-account|unblock-account|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${account}" ]
    then
        Usage 2
        LogError "action '${action}' requires to specify account: --account="
        exit 1
    fi

    if [ "${action}" = "get-account" ] && [ "${blocked}" = "true" ]
    then
        if [ "${enabled}" = "true" ] || [ "${disabled}" = "true" ]
        then
            Usage 2
            LogError "Action 'get-account' for blocked accounts denies use of --enabled, --disabled switches"
            exit 1
        fi
    fi

    if [ "${action}" = "set-account-password" ] && [ -z "${account_password}" ]
    then
        Usage 2
        LogError "Action 'set-account-password' requires to specify password: --account-password="
        exit 1
    fi

    actions="|store-role|rename-role|remove-role|get-permission|set-permission|rename-permission|remove-permission|get-folder|set-folder|rename-folder|remove-folder|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${role}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify role: --role="
        exit 1
    fi

    if [ "${action}" = "rename-role" ] && [ -z "${new_role}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify new role: --new-role="
        exit 1
    fi

    actions="|set-permission|rename-permission|remove-permission|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${permission}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify permission: --permission="
        exit 1
    fi

    if [ "${action}" = "rename-permission" ] && [ -z "${new_permission}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify new permission: --new-permission="
        exit 1
    fi

    actions="|set-folder|rename-folder|remove-folder|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${folder}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify folder: --folder="
        exit 1
    fi

    if [ "${action}" = "rename-folder" ] && [ -z "${new_folder}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify new folder: --new-folder="
        exit 1
    fi

    if [ "${action}" = "store-service" ] 
    then
        if [ -z "${service_type}" ]
        then
            Usage 2
            LogError "Action '${action}' requires to specify service type: --service-type="
            exit 1
        fi

        if [ "${authentication_scheme}" = "TWO-FACTOR" ] && [ -z "${second_service}" ]
        then
            Usage 2
            LogError "Action '${action}' using authentication scheme TWO-FACTOR requires to specify the second service: --second-service="
            exit 1
        fi

        if [ -n "${second_service}" ]
        then
            if  [ -n "${authentication_scheme}" ] && [ ! "${authentication_scheme}" = "TWO-FACTOR" ]
            then
                Usage 2
                LogError "Action '${action}' using --second-service option requires to specify authentication scheme TWO-FACTOR: --authentication-scheme=TWO-FACTOR"
                exit 1
            fi

            if [ -z "${authentication_scheme}" ]
            then
                authentication_scheme=TWO-FACTOR
            fi
        fi
    fi

    if [ "${action}" = "rename-service" ] && [ -z "${new_service}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify new service: --new-service="
        exit 1
    fi

    if [ "${action}" = "store-service-settings" ] && [ -z "${settings}" ]
    then
        Usage 2
        LogError "Action '${action}' requires to specify settings: --settings="
        exit 1
    fi

    if [ "${action}" = "get-service-settings" ] || [ "${action}" = "store-service-settings" ]
    then
        if [ -z "${service_type}" ]
        then
            Usage 2
            LogError "Action '${action}' requires to specify the service type: --service-type="
            exit 1
        fi
    fi

    if [ -n "${show_logs}" ] && [ -z "${log_dir}" ]
    then
        Usage 2
        LogError "Log directory not specified and --show-logs switch is present: --log-dir="
        exit 1
    fi

    if [ -z "${make_dirs}" ] && [ -n "${log_dir}" ] && [ ! -d "${log_dir}" ]
    then
        Usage 2
        LogError "Log directory not found and --make-dirs switch not present: --log-dir=${log_dir}"
        exit 1
    fi

    # initialize logging
    if [ -n "${log_dir}" ]
    then
        # create log directory if required
        if [ ! -d "${log_dir}" ] && [ -n "${make_dirs}" ]
        then
            mkdir -p "${log_dir}"
        fi
    
        log_file="${log_dir}"/deploy-identity-service."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/deploy-identity-service."${start_time}".log
        done
        
        touch "${log_file}"
    fi

    LogVerbose "-- begin of log --------------"
    LogVerbose "$0" "$(echo "${args}" | sed 's/--password=\([^--]*\)//')"
    LogVerbose "-- begin of output -----------"
}

# ------------------------------
# Main
# ------------------------------

Process()
{
    LogVerbose ".. Processing"

    Login

    case "${action}" in
        get-account)        if [ "${blocked}" = "true" ]
                            then
                                Get_Blocked_Account
                            else
                                Get_Account
                            fi
                            ;;
        store-account)      Store_Account
                            ;;
        rename-account)     Rename_Account
                            ;;
        remove-account)     Remove_Account
                            ;;
        get-account-permission)  Get_Account_Permission
                            ;;
        set-account-password)    Set_Account_Password
                            ;;
        reset-account-password)  Reset_Account_Password
                            ;;
        enable-account)     Enable_Account
                            ;;
        disable-account)    Disable_Account
                            ;;
        block-account)      Block_Account
                            ;;
        unblock-account)    Unblock_Account
                            ;;
        get-role)           Get_Role
                            ;;
        store-role)         Store_Role
                            ;;
        rename-role)        Rename_Role
                            ;;
        remove-role)        Remove_Role
                            ;;
        get-permission)     Get_Permission
                            ;;
        set-permission)     Set_Permission
                            ;;
        rename-permission)  Rename_Permission
                            ;;
        remove-permission)  Remove_Permission
                            ;;
        get-folder)         Get_Folder_Permisions
                            ;;
        set-folder)         Set_Folder_Permisions
                            ;;
        rename-folder)      Rename_Folder_Permisions
                            ;;
        remove-folder)      Remove_Folder_Permisions
                            ;;
        get-service)        Get_Identity_Service
                            ;;
        store-service)      Store_Identity_Service
                            ;;
        rename-service)     Rename_Identity_Service
                            ;;
        remove-service)     Remove_Identity_Service
                            ;;
        get-service-settings)   Get_Identity_Service_Settings
                                ;;
        store-service-settings) Store_Identity_Service_Settings
                                ;;
    esac

    Logout
}

# ------------------------------
# Cleanup trap
# ------------------------------

End()
{
    if [ -n "${access_token}" ]
    then
        Logout
    fi

    if [ "$1" = "EXIT" ]
    then
        LogVerbose "-- end of log ----------------"

        if [ -n "${show_logs}" ] && [ -f "${log_file}" ]
        then
            cat "${log_file}"
        fi        
    fi

    unset joc_url
    unset joc_cacert
    unset joc_client_cert
    unset joc_client_key
    unset joc_user
    unset joc_password
    unset timeout

    unset make_dirs
    unset show_logs
    unset verbose
    unset log_dir

    unset controller_id
    unset account
    unset new_account
    unset account_password
    unset new_password
    unset comment

    unset service
    unset service_type
    unset ordering
    unset new_service
    unset second_service
    unset authentication_scheme
    unset settings

    unset role
    unset new_role

    unset permission
    unset new_permission

    unset folder
    unset new_folder

    unset force_password_change
    unset enabled
    unset disabled
    unset blocked
    unset excluded
    unset required
    unset recursive

    unset audit_message
    unset audit_time_spent
    unset audit_link

    unset log_file
    unset start_time

    unset response_json
    unset access_token
    unset curl_options
    unset action

    set +e
}

# ------------------------------
# Enable trap and start
# ------------------------------

trap 'End EXIT' EXIT
trap 'End SIGTERM' TERM
trap 'End SIGINT' INT

Arguments "$@"
Process
