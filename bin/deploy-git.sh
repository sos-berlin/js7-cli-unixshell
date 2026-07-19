#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2025-01-23
# Purpose:  Deployment Operations for Git Reepositories
# ------------------------------------------------------------
#
# Examples:
#
# set common options for connection to the JS7 REST Web Service
# request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password=root --controller-id=testsuite --ca-cert=./root-ca.crt)
#
# store credentials
# ./deploy-git.sh store-credentials  "${request_options[@]}" --server=github.com --user-account=community \
#                                                            --user-name="Community" --user-mail="community@example.com" \
#                                                            --user-password=secret
# clone repository
# ./deploy-git.sh clone    "${request_options[@]}" --folder=/TestRepo --remote-url="git@github.com:sos-berlin/js7-demo-inventory-rollout-test"
#
# store items to rollout respository: folder
# ./deploy-git.sh store-item  "${request_options[@]}" --folder=/TestRepo --recursive
#
# add items to repository
# ./deploy-git.sh add      "${request_options[@]}" --folder=/TestRepo
#
# commit changes to repository
# ./deploy-git.sh commit   "${request_options[@]}" --folder=/TestRepo --message="v.1.23.34"
#
# push changes to remote repository
# ./deploy-git.sh push     "${request_options[@]}" --folder=/TestRepo


# ------------------------------
# Global script variables
# ------------------------------

joc_url=
joc_user=
joc_password=
joc_cacert=
joc_client_cert=
joc_client_key=
controller_id=
timeout=60
make_dirs=
show_logs=
log_dir=
log_dir=
verbose=0
action=
jq_options=-cM

item=
start_time=$(date +"%Y-%m-%dT%H-%M-%S")
response_json=
changes_json=
access_token=

folder=
recursive=false
object_path=
object_type=
category=ROLLOUT
change=
no_referencing=0
no_references=0
branch=
tag=
message=
server=

user_account=
user_name=
user_mail=
user_password=
user_access_token=
user_private_key=
remote_url=

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

AskUserPassword() {
    user_password="$(
        exec < /dev/tty || exit
        tty_config=$(stty -g) || exit
        trap 'stty "$tty_config"' EXIT INT TERM
        stty -echo || exit
        printf 'Git Account Password: ' > /dev/tty
        IFS= read -r user_password; rc=$? 2> /dev/tty
        echo > /dev/tty
        printf '%s\n' "${user_password}"
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

Get_Changes()
{
    LogVerbose ".. Get_Changes()"
    Curl_Options

    request_body="{ \"names\": ["
    comma=
    set -- "$(echo "${change}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done

    request_body="${request_body} ], \"details\": true }"

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/changes"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/changes)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.changes[] // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Changes() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Changes() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Changes() failed: ${response_json}"
        exit 4
    fi

    echo "${response_json}" | jq -r '.'
}

Get_Change_Dependencies()
{
    LogVerbose ".. Get_Dependencies()"
    Curl_Options

    request_body=$(echo "${changes_json}" | jq -c '{operationType: "DEPLOY", configurations: [(.changes[].configurations[] | {name: .name, type: .objectType} )]}')
        
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/dependencies"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/dependencies)
    # LogVerbose ".... response:"
    # LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.dependencies // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Dependencies() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Dependencies() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Dependencies() failed: ${response_json}"
        exit 4
    fi

    if [ "${no_referencing}" -eq 0 ]
    then
        if [ -n "${folder}" ]
        then
            referencing_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.dependencies.requestedItems[].referencedBy[] | select(.path | startswith('\"$folder/\"')) | {path: .path, name: .name, objectType: .objectType} )] }] }')
        else
            referencing_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.dependencies.requestedItems[].referencedBy[] | {path: .path, name: .name, objectType: .objectType} )] }] }')
        fi

        LogVerbose ".... response for referencing objects:"
        LogVerbose "${referencing_json}"
    else
        referencing_json="{\"changes\": []}"
    fi

    if [ "${no_references}" -eq 0 ]
    then
        if [ -n "${folder}" ]
        then
            referenced_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.dependencies.requestedItems[].references[] | select(.path | startswith('\"$folder/\"')) | {path: .path, name: .name, objectType: .objectType} )] }] }')
        else
            referenced_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.dependencies.requestedItems[].references[] | {path: .path, name: .name, objectType: .objectType} )] }] }')
        fi

        LogVerbose ".... response for referenced objects:"
        LogVerbose "${referenced_json}"
    else
        referenced_json="{\"changes\": []}"
    fi

    if [ -n "${folder}" ]
    then
        response_json=$(jq --argjson changes "${changes_json}" --argjson referencing "${referencing_json}" --argjson referenced "${referenced_json}" -n "${jq_options}" '{changes: [{ configurations: [($changes, $referencing, $referenced | .changes[].configurations[] | select(.path | startswith('\"$folder/\"')) | {path: .path, objectType: .objectType})] | unique }] }')
    else
        response_json=$(jq --argjson changes "${changes_json}" --argjson referencing "${referencing_json}" --argjson referenced "${referenced_json}" -n "${jq_options}" '{changes: [{ configurations: [($changes, $referencing, $referenced | .changes[].configurations[] | {path: .path, objectType: .objectType})] | unique }] }')
    fi

    LogVerbose ".... response for changes and dependencies:"
    LogVerbose "${response_json}"

    echo "${response_json}" | jq -r '.'
}

List_Item()
{
    LogVerbose ".. List_Item()"
    Curl_Options

    request_body="{ \"folder\": \"${folder}\", \"recursive\": ${recursive}, \"category\": \"${category}\" }"

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/read"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/read)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.path // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "List_Item() could not find objects: ${response_json}"
                exit 3
            else
                LogError "List_Item() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "List_Item() failed: ${response_json}"
        exit 4
    fi
    
    echo "${response_json}" | jq -r '.'
}

Update_Item()
{
    if [ -n "${change}" ]
    then
        changes_json=$(Get_Changes)
        
        if [ "${no_referencing}" -eq 0 ] || [ "${no_references}" -eq 0 ]
        then
            changes_json=$(Get_Change_Dependencies)
        fi
    else
        changes_json=
    fi

    LogVerbose ".. Update_Item()"
    Curl_Options

    request_body="{"

    if [ -n "${object_path}" ]
    then
        request_body="${request_body} \"configurations\": [ "
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\" } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi
    
    if [ -n "${folder}" ] && [ -z "${change}" ]
    then
        request_body="${request_body} \"configurations\": [ "
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"FOLDER\" } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${change}" ] && [ -n "${changes_json}" ]
    then
        request_body=$(echo "${request_body} \"configurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{configurations: [(.changes[].configurations[] | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
    fi    

    request_body="${request_body}, \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/update"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/update)
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
                LogWarning "Update_Item() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Update_Item() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Update_Item() failed: ${response_json}"
        exit 4
    fi
}

Store_Item()
{
    if [ -n "${change}" ]
    then
        changes_json=$(Get_Changes)
        
        if [ "${no_referencing}" -eq 0 ] || [ "${no_references}" -eq 0 ]
        then
            changes_json=$(Get_Change_Dependencies)
        fi
    else
        changes_json=
    fi

    LogVerbose ".. Store_Item()"
    Curl_Options

    request_body="{"
    comma=

    if [ -n "${controller_id}" ]
    then
        request_body="${request_body}${comma} \"controllerId\": \"${controller_id}\""
        comma=,
    fi

    if [ "${category}" = "LOCAL" ]
    then
        request_body="${request_body}${comma} \"local\": {"
    else
        request_body="${request_body}${comma} \"rollout\": {"
    fi

    if [ -n "${object_path}" ]
    then
        request_body="${request_body} \"draftConfigurations\": ["
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\" } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi
    
    if [ -n "${folder}" ] && [ -z "$change" ]
    then
        request_body="${request_body} \"draftConfigurations\": ["
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"FOLDER\", \"recursive\": ${recursive} } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi
    
    if [ -n "${change}" ] && [ -n "${changes_json}" ]
    then
        request_body=$(echo "${request_body} \"draftConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{draftConfigurations: [(.changes[].configurations[] | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
    fi    

    request_body="${request_body} }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/store)
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
                LogWarning "Store_Item() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Item() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Item() failed: ${response_json}"
        exit 4
    fi
}

Delete_Item()
{
    if [ -n "${change}" ]
    then
        changes_json=$(Get_Changes)
        
        if [ "${no_referencing}" -eq 0 ] || [ "${no_references}" -eq 0 ]
        then
            changes_json=$(Get_Change_Dependencies)
        fi
    else
        changes_json=
    fi

    LogVerbose ".. Delete_Item()"
    Curl_Options

    request_body="{"

    if [ -n "${object_path}" ]
    then
        request_body="${request_body} \"configurations\": [ "
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\" } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi
    
    if [ -n "${folder}" ] && [ -z "${change}" ]
    then
        request_body="${request_body} \"configurations\": [ "
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"FOLDER\" } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${change}" ] && [ -n "${changes_json}" ]
    then
        request_body=$(echo "${request_body} \"configurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{configurations: [(.changes[].configurations[] | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
    fi    

    request_body="${request_body}, \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/delete)
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
                LogWarning "Delete_Item() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Item() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Item() failed: ${response_json}"
        exit 4
    fi
}

Git_Checkout()
{
    LogVerbose ".. Git_Checkout()"
    Curl_Options

    request_body="{"
    request_comma=

    if [ -n "${branch}" ]
    then
        request_body="${request_body}${request_comma} \"branch\": \"${branch}\""
        request_comma=,
    fi

    if [ -n "${tag}" ]
    then
        request_body="${request_body}${request_comma} \"tag\": \"${tag}\""
        request_comma=,
    fi

    request_body="${request_body}${request_comma} \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/checkout"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/checkout)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Checkout() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Checkout() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Checkout() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Checkout() failed: ${response_json}"
        exit 4
    fi
}

Git_Clone()
{
    LogVerbose ".. Git_Clone()"
    Curl_Options

    request_body="{ \"remoteUrl\": \"${remote_url}\", \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/clone"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/clone)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Clone() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Clone() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Clone() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Clone() failed: ${response_json}"
        exit 4
    fi
}

Git_Add()
{
    LogVerbose ".. Git_Add()"
    Curl_Options

    request_body="{ \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/add"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/add)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Add() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Add() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Add() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Add() failed: ${response_json}"
        exit 4
    fi
}

Git_Commit()
{
    LogVerbose ".. Git_Commit()"
    Curl_Options

    request_body="{ \"message\": \"${message}\", \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/commit"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/commit)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Commit() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Commit() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Commit() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Commit() failed: ${response_json}"
        exit 4
    fi

    # return commit hash
    echo "${response_json}" | jq -r '.stdOut' | grep -E '^\[.* +([0-9a-z]+)\]' | cut -f2 -d' '
}

Git_Push()
{
    LogVerbose ".. Git_Push()"
    Curl_Options

    request_body="{ \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/push"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/push)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Push() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Push() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Push() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Push() failed: ${response_json}"
        exit 4
    fi
}

Git_Pull()
{
    LogVerbose ".. Git_Pull()"
    Curl_Options

    request_body="{ \"folder\": \"${folder}\", \"category\": \"${category}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/pull"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/pull)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.exitCode // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Git_Pull() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Git_Pull() failed: ${response_json}"
                exit 4
            fi
        else
            if [ "${ok}" -ne 0 ]
            then
                LogError "Git_Pull() failed with exit code ${ok}: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Git_Pull() failed: ${response_json}"
        exit 4
    fi
}

Get_Credentials()
{
    LogVerbose ".. Get_Credentials()"
    Curl_Options

    request_body="{}"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/credentials"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/credentials)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.credentials[].gitAccount // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Credentials() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Credentials() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Credentials() failed: ${response_json}"
        exit 4
    fi

    echo "${response_json}" | jq -r '.'
}

Store_Credentials()
{
    LogVerbose ".. Store_Credentials()"
    Curl_Options

    request_body="{}"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/credentials"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/credentials)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.credentials[].gitAccount // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ -n "${error_code}" ]
            then
                if [ "${error_code}" = "JOC-400" ]
                then
                    LogWarning "Get_Credentials() could not find objects: ${response_json}"
                    exit 3
                else
                    LogError "Get_Credentials() failed: ${response_json}"
                    exit 4
                fi
            fi
        else
            Delete_Credentials
        fi
    fi    

    request_body="{ \"credentials\": ["
    comma=
    set -- "$(echo "${server}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} { \"gitAccount\": \"${user_account}\", \"username\": \"${user_name}\", \"email\": \"${user_mail}\"" 
        
        if [ -n "${user_password}" ]
        then
            request_body="${request_body}, \"password\": \"${user_password}\""
        fi

        if [ -n "${user_access_token}" ]
        then
            request_body="${request_body}, \"personalAccessToken\": \"${user_access_token}\""
        fi

        if [ -n "${user_private_key}" ]
        then
            request_body="${request_body}, \"keyfilePath\": \"${user_private_key}\""
        fi

        request_body="${request_body}, \"gitServer\": \"${i}\" }"
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/credentials/add"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/credentials/add)
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
                LogWarning "Store_Credentials() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Credentials() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Credentials() failed: ${response_json}"
        exit 4
    fi
}

Delete_Credentials()
{
    LogVerbose ".. Delete_Credentials()"
    Curl_Options

    request_body="{ \"gitServers\": ["
    comma=
    set -- "$(echo "${server}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"
    
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/repository/git/credentials/remove"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/repository/git/credentials/remove)
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
                LogWarning "Delete_Credentials() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Credentials() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Credentials() failed: ${response_json}"
        exit 4
    fi
}

Usage()
{
    >&"$1" echo ""
    >&"$1" echo "Usage: $(basename "$0") [Command] [Options] [Switches]"
    >&"$1" echo ""
    >&"$1" echo "  Commands:"
    >&"$1" echo "    list-item           --folder [--recursive] [--local]"
    >&"$1" echo "    store-item         [--path]  [--type] [--folder] [--recursive] [--local] [--controller-id]"
    >&"$1" echo "                                 [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    update-item        [--path]  [--type] [--folder] [--recursive] [--local]"
    >&"$1" echo "                                 [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    delete-item        [--path]  [--type] [--folder] [--local]"
    >&"$1" echo "                                 [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    clone               --folder [--local] --remote-url"
    >&"$1" echo "    checkout            --folder [--local] [--branch | --tag]"
    >&"$1" echo "    add                 --folder [--local]"
    >&"$1" echo "    commit              --folder [--local] --message"
    >&"$1" echo "    push                --folder [--local]"
    >&"$1" echo "    pull                --folder [--local]"
    >&"$1" echo "    get-credentials"
    >&"$1" echo "    store-credentials   --server --user-account --user-name --user-mail"
    >&"$1" echo "                                [--user-password | --user-access-token | --user-private-key]"
    >&"$1" echo "    delete-credentials  --server"
    >&"$1" echo ""
    >&"$1" echo "  Options:"
    >&"$1" echo "    --url=<url>                        | required: JOC Cockpit URL"
    >&"$1" echo "    --controller-id=<id>               | required: Controller ID"
    >&"$1" echo "    --user=<account>                   | required: JOC Cockpit user account"
    >&"$1" echo "    --password=<password>              | optional: JOC Cockpit password"
    >&"$1" echo "    --ca-cert=<path>                   | optional: path to CA Certificate used for JOC Cockpit login"
    >&"$1" echo "    --client-cert=<path>               | optional: path to Client Certificate used for login"
    >&"$1" echo "    --client-key=<path>                | optional: path to Client Key used for login"
    >&"$1" echo "    --timeout=<seconds>                | optional: timeout for request, default: ${timeout}"
    >&"$1" echo "    --folder=<folder[,folder]>         | optional: inventory folders holding objects"
    >&"$1" echo "    --path=<path[,path]>               | optional: inventory paths to objects"
    >&"$1" echo "    --type=<type>                      | optional: object type such as WORKFLOW, SCHEDULE"
    >&"$1" echo "    --change=<change[,change]>         | optional: inventory changes of objects"
    >&"$1" echo "    --branch=<identifier>              | optional: Git branch identified by name, default: master"
    >&"$1" echo "    --tag=<tag[,tag]>                  | optional: Git branch identified by tags"
    >&"$1" echo "    --message=<text>                   | optional: Git commit message"
    >&"$1" echo "    --server=<host>                    | optional: Git server"
    >&"$1" echo "    --user-account=<account>           | optional: Git authentication user account"
    >&"$1" echo "    --user-name=<text>                 | optional: Git authentication user name"
    >&"$1" echo "    --user-mail=<e-mail>               | optional: Git authentication user e-mail address"
    >&"$1" echo "    --user-password=<password>         | optional: Git authentication user password"
    >&"$1" echo "    --user-access-token=<token>        | optional: Git authentication user access token"
    >&"$1" echo "    --user-private-key=<path>          | optional: Git authentication user private key file"
    >&"$1" echo "    --remote-url=<url>                 | optional: Git remote repository URL"
    >&"$1" echo "    --audit-message=<string>           | optional: audit log message"
    >&"$1" echo "    --audit-time-spent=<number>        | optional: audit log time spent in minutes"
    >&"$1" echo "    --audit-link=<url>                 | optional: audit log link"
    >&"$1" echo "    --log-dir=<directory>              | optional: path to directory holding the script's log files"
    >&"$1" echo ""
    >&"$1" echo "  Switches:"
    >&"$1" echo "    -h | --help                        | displays usage"
    >&"$1" echo "    -v | --verbose                     | displays verbose output, repeat to increase verbosity"
    >&"$1" echo "    -p | --password                    | asks for password"
    >&"$1" echo "    -l | --local                       | uses repository for local objects"
    >&"$1" echo "    -r | --recursive                   | specifies folders to be looked up recursively"
    >&"$1" echo "    -u | --user-password               | asks for Git account password"
    >&"$1" echo "    --no-referencing                   | excludes referencing objects when used with --change"
    >&"$1" echo "    --no-references                    | excludes referenced objects when used with --change"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/X7sqCg"
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
        list-item|store-item|update-item|delete-item|checkout|clone|add|commit|push|pull|get-credentials|store-credentials|delete-credentials) action=$1
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
            --controller-id=*)      controller_id=$(echo "${option}" | sed 's/--controller-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --timeout=*)            timeout=$(echo "${option}" | sed 's/--timeout=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --folder=*)             folder=$(echo "${option}" | sed 's/--folder=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --path=*)               object_path=$(echo "${option}" | sed 's/--path=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --type=*)               object_type=$(echo "${option}" | sed 's/--type=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --change=*)             change=$(echo "${option}" | sed 's/--change=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --branch=*)             branch=$(echo "${option}" | sed 's/--branch=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --tag=*)                tag=$(echo "${option}" | sed 's/--tag=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --message=*)            message=$(echo "${option}" | sed 's/--message=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --server=*)             server=$(echo "${option}" | sed 's/--server=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-account=*)       user_account=$(echo "${option}" | sed 's/--user-account=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-name=*)          user_name=$(echo "${option}" | sed 's/--user-name=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-mail=*)          user_mail=$(echo "${option}" | sed 's/--user-mail=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-password=*)      user_password=$(echo "${option}" | sed 's/--user-password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-access-token=*)  user_access_token=$(echo "${option}" | sed 's/--user-access-token=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --user-private-key=*)   user_private_key=$(echo "${option}" | sed 's/--user-private-key=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --remote-url=*)         remote_url=$(echo "${option}" | sed 's/--remote-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
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
            -h|--help)              Usage 1
                                    exit
                                    ;;
            -v|--verbose)           verbose=$((verbose + 1))
                                    jq_options=-M
                                    ;;
            -p|--password)          AskPassword
                                    ;;
            --no-referencing)       no_referencing=1
                                    ;;
            --no-references)        no_references=1
                                    ;;
            -l|--local)             category=LOCAL
                                    ;;
            -r|--recursive)         recursive=true
                                    ;;
            -u|--user-password)     AskUserPassword
                                    ;;
            --make-dirs)            make_dirs=1
                                    ;;
            --show-logs)            show_logs=1
                                    ;;
            list-item|store-item|update-item|delete-item|checkout|clone|add|commit|push|pull|get-credentials|store-credentials|delete-credentials)
                                    ;;
            *)                      Usage 2
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

    actions="|unknown|"
    if [[ "${actions}" != *"|${action}|"* ]]
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
            Usage 2
            LogError "Client Certificate file not found: --client-cert=${joc_client_cert}"
            exit 1
        fi
    
        if [ -n "${joc_client_key}" ] && [ ! -f "${joc_client_key}" ]
        then
            Usage 2
            LogError "Client Private Key file not found: --client-key=${joc_client_key}"
            exit 1
        fi
    
        if [ -z "${controller_id}" ]
        then
            Usage 2
            LogError "Controller ID must be specified: --controller-id=<identifier>"
            exit 1
        fi
    fi

    actions="|list-item|checkout|clone|add|commit|push|pull|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${folder}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify a folder: --folder="
        exit 1
    fi

    actions="|store-item|update-item|delete-item|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        count=0

        if [ -n "${object_path}" ]
        then
            count=$((count+1))
        fi

        if [ -n "${folder}" ]
        then
            count=$((count+1))
        fi

        if [ -n "${change}" ]
        then
            count=$((count+1))
        fi

        if [ "${count}" -eq 0 ]
        then
            Usage 2
            LogError "Action '${action}' requires to specify path, folder or change: --path=, --folder=, --change="
            exit 1
        fi

        if [ "${count}" -gt 1 ]
        then
            if [ "${count}" -eq 2 ] && [ -n "${folder}" ] && [ -n "${change}" ]
            then
                count=0
            else
                Usage 2
                LogError "Action '${action}' allows to specify only one of path, folder or change: --path=, --folder=, --change="
                exit 1
            fi
        fi
    fi

    if [ "${action}" = "checkout" ]
    then
        if [ -z "${branch}" ] && [ -z "${tag}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify one of --branch or --tag"
            exit 1
        fi

        if [ -n "${branch}" ] && [ -n "${tag}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify only one of --branch or --tag"
            exit 1
        fi
    fi

    if [ "${action}" = "clone" ] && [ -z "${remote_url}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify the remote repository URL: --remote-url="
        exit 1
    fi

    if [ "${action}" = "commit" ] && [ -z "${message}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify a commit message: --message="
        exit 1
    fi

    actions="|store-credentials|delete-credentials|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${server}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify the Git Server: --server"
        exit 1
    fi

    actions="|store-credentials|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        if [ -z "${user_account}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify the user account: --user-account"
            exit 1
        fi

        if [ -z "${user_name}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify the user name: --user-name"
            exit 1
        fi

        if [ -z "${user_mail}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify the user mail: --user-mail"
            exit 1
        fi

        if [ -z "${user_password}" ] && [ -z "${user_access_token}" ] && [ -z "${user_private_key}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify one of: --user-password, --user-access-token, --user-private-key"
            exit 1
        fi

        if [ -n "${user_password}" ] 
        then
            if [ -n "${user_access_token}" ] || [ -n "${user_private_key}" ]
            then
                Usage 2
                LogError "Command '${action}' requires to specify only one of: --user-password, --user-access-token, --user-private-key"
                exit 1
            fi
        fi

        if [ -n "${user_access_token}" ] 
        then
            if [ -n "${user_password}" ] || [ -n "${user_private_key}" ]
            then
                Usage 2
                LogError "Command '${action}' requires to specify only one of: --user-password, --user-access-token, --user-private-key"
                exit 1
            fi
        fi

        if [ -n "${user_private_key}" ] 
        then
            if [ -n "${user_access_token}" ] || [ -n "${user_password}" ]
            then
                Usage 2
                LogError "Command '${action}' requires to specify only one of: --user-password, --user-access-token, --user-private-key"
                exit 1
            fi
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
    
        log_file="${log_dir}"/deploy-git."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/deploy-git."${start_time}".log
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
        list-item)          List_Item
                            ;;
        store-item)         Store_Item
                            ;;
        update-item)        Update_Item
                            ;;
        delete-item)        Delete_Item
                            ;;
        checkout)           Git_Checkout
                            ;;
        clone)              Git_Clone
                            ;;
        add)                Git_Add
                            ;;
        commit)             Git_Commit
                            ;;
        push)               Git_Push
                            ;;
        pull)               Git_Pull
                            ;;
        get-credentials)    Get_Credentials
                            ;;
        store-credentials)  Store_Credentials
                            ;;
        delete-credentials) Delete_Credentials
                            ;;
    esac

    Logout
}

# ------------------------------
# Cleanup trap
# ------------------------------

End()
{
    if [ "$1" = "EXIT" ]
    then
        LogVerbose "-- end of log ----------------"

        if [ -n "${show_logs}" ] && [ -f "${log_file}" ]
        then
            cat "${log_file}"
        fi        
    fi

    unset script_home
    unset joc_url
    unset joc_cacert
    unset joc_client_cert
    unset joc_client_key
    unset joc_user
    unset joc_password
    unset controller_id
    unset timeout

    unset make_dirs
    unset show_logs
    unset verbose
    unset log_dir

    unset folder
    unset object_path
    unset object_type
    unset category
    unset change
    unset no_referencing
    unset no_references
    unset branch
    unset tag
    unset message
    unset server

    unset user_account
    unset user_name
    unset user_mail
    unset user_password
    unset user_access_token
    unset user_private_key
    unset remote_url

    unset audit_message
    unset audit_time_spent
    unset audit_link

    unset log_file
    unset start_time

    unset response_json
    unset access_token
    unset curl_options
    unset curl_log_options
    unset action
    unset jq_options

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
