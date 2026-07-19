#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2024-08-24
# Purpose:  Deployment Operations on Workflows
# ------------------------------------------------------------
#
# Examples, see https://kb.sos-berlin.com/x/-YZvCQ

# request_options=(--url=http://localhost:4446 --user=root --password=root)  
#
# restart Standalone Controller
# ./operate-controller.sh restart ${request_options[@]} --controller-id=controller
#
# restart Controller Cluster
#./operate-controller.sh restart ${request_options[@]} --controller-id=controller_cluster --controller-url=http://localhost:9544
#
# reset Standalone Agent
# /operate-controller.sh reset-agent ${request_options[@]} --controller-id=controller --agent-id=StandaloneAgent
#
# reset/force Agent Cluster
# /operate-controller.sh reset-agent ${request_options[@]} --controller-id=controller_cluster --agent-id=ClusterAgent --force

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
controller_url=
agent_id=
subagent_id=
state=
switch_over=false
force=false
no_hidden=false
version=
list=0

key_file=
cert_file=
key_password=
in=
infile=
outfile=
java_home=
java_bin=
java_lib="${script_home}"/lib

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

AskKeyPassword() {
    key_password="$(
        exec < /dev/tty || exit
        tty_config=$(stty -g) || exit
        trap 'stty "$tty_config"' EXIT INT TERM
        stty -echo || exit
        printf 'Keystore/Key Password: ' > /dev/tty
        IFS= read -r key_password; rc=$? 2> /dev/tty
        echo > /dev/tty
        printf '%s\n' "${key_password}"
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

Terminate_Controller()
{
    LogVerbose ".. Terminate_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${controller_url}" ]
    then
        request_body="${request_body}, \"url\": \"${controller_url}\""
    fi

    request_body="${request_body}, \"withSwitchover\": ${switch_over}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/terminate"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/terminate)    
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        # Standalone Controller response
        ok=$(echo "${response_json}" | jq -r '.ok // empty' | sed 's/^"//' | sed 's/"$//')

        if [ -z "${ok}" ]
        then
            # Controller Cluster response
            ok=$(echo "${response_json}" | jq -r '.roles // empty' | sed 's/^"//' | sed 's/"$//')
        fi

        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Terminate_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Terminate_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Terminate_Controller() failed: ${response_json}"
        exit 4
    fi
}

Terminate_Restart_Controller()
{
    LogVerbose ".. Terminate_Restart_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${controller_url}" ]
    then
        request_body="${request_body}, \"url\": \"${controller_url}\""
    fi

    request_body="${request_body}, \"withSwitchover\": ${switch_over}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/restart"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/restart)    
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
                LogWarning "Terminate_Restart_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Terminate_Restart_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Terminate_Restart_Controller() failed: ${response_json}"
        exit 4
    fi
}

Cancel_Controller()
{
    LogVerbose ".. Cancel_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${controller_url}" ]
    then
        request_body="${request_body}, \"url\": \"${controller_url}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/abort"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/abort)    
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
                LogWarning "Cancel_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Cancel_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Cancel_Controller() failed: ${response_json}"
        exit 4
    fi
}

Cancel_Restart_Controller()
{
    LogVerbose ".. Cancel_Restart_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${controller_url}" ]
    then
        request_body="${request_body}, \"url\": \"${controller_url}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/abort_and_restart"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/abort_and_restart)    
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
                LogWarning "Cancel_Restart_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Cancel_Restart_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Cancel_Restart_Controller() failed: ${response_json}"
        exit 4
    fi
}

Switchover_Controller()
{
    LogVerbose ".. Switchover_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/cluster/switchover"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/cluster/switchover)    
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
                LogWarning "Switchover_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Switchover_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Switchover_Controller() failed: ${response_json}"
        exit 4
    fi
}

Appoint_Nodes_Controller()
{
    LogVerbose ".. Appoint_Nodes_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/cluster/appoint_nodes"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/cluster/appoint_nodes)    
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
                LogWarning "Appoint_Nodes_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Appoint_Nodes_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Appoint_Nodes_Controller() failed: ${response_json}"
        exit 4
    fi
}

Confirm_Node_Loss_Controller()
{
    LogVerbose ".. Confirm_Node_Loss_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/cluster/confirm_node_loss"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/cluster/confirm_node_loss)    
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
                LogWarning "Confirm_Node_Loss_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Confirm_Node_Loss_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Confirm_Node_Loss_Controller() failed: ${response_json}"
        exit 4
    fi
}

Status_Controller()
{
    LogVerbose ".. Status_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\"" 
    
    if [ -n "${controller_url}" ]
    then
        request_body="${request_body}, \"url\": \"${controller_url}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller)    
    LogVerbose ".... response:"
    Log "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.controller // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Status_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Status_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Status_Controller() failed: ${response_json}"
        exit 4
    fi
}

Check_Controller()
{
    LogVerbose ".. Check_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"url\": \"${controller_url}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/test"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/test)    
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.controller // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Check_Controller() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Check_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Check_Controller() failed: ${response_json}"
        exit 4
    fi
}

Enable_Standalone_Agent()
{
    LogVerbose ".. Enable_Standalone_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    
    if [ -n "${agent_id}" ]
    then
        request_body="${request_body}, \"agentIds\": ["
        comma=
        set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/enable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/enable)    
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
                LogWarning "Enable_Standalone_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Enable_Standalone_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Enable_Standalone_Agent() failed: ${response_json}"
        exit 4
    fi
}

Disable_Standalone_Agent()
{
    LogVerbose ".. Disable_Standalone_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    
    if [ -n "${agent_id}" ]
    then
        request_body="${request_body}, \"agentIds\": ["
        comma=
        set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/disable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/disable)    
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
                LogWarning "Disable_Standalone_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Disable_Standalone_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Disable_Standalone_Agent() failed: ${response_json}"
        exit 4
    fi
}

Status_Agent()
{
    LogVerbose ".. Status_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${agent_id}" ]
    then
        request_body="${request_body}, \"agentIds\": ["
        comma=
        set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${state}" ]
    then
        request_body="${request_body}, \"states\": ["
        comma=
        set -- "$(echo "${state}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"onlyVisibleAgents\": ${no_hidden}"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents)    
    LogVerbose ".... response:"
    Log "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.agents // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Status_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Status_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Status_Agent() failed: ${response_json}"
        exit 4
    fi
}

Reset_Agent()
{
    LogVerbose ".. Reset_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentId\": \"${agent_id}\", \"force\": ${force}"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agent/reset"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agent/reset)    
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
                LogWarning "Reset_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Reset_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Reset_Agent() failed: ${response_json}"
        exit 4
    fi
}

Switchover_Agent()
{
    LogVerbose ".. Switchover_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentId\": \"${agent_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agent/cluster/switchover"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agent/cluster/switchover)    
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
                LogWarning "Switchover_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Switchover_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Switchover_Agent() failed: ${response_json}"
        exit 4
    fi
}

Confirm_Node_Loss_Agent()
{
    LogVerbose ".. Confirm_Node_Loss_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentId\": \"${agent_id}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agent/cluster/confirm_node_loss"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agent/cluster/confirm_node_loss)    
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
                LogWarning "Confirm_Node_Loss_Agent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Confirm_Node_Loss_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Confirm_Node_Loss_Agent() failed: ${response_json}"
        exit 4
    fi
}

Enable_Subagent()
{
    LogVerbose ".. Enable_Subagent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    
    if [ -n "${subagent_id}" ]
    then
        request_body="${request_body}, \"subagentIds\": ["
        comma=
        set -- "$(echo "${subagent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/subagents/enable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/subagents/enable)    
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
                LogWarning "Enable_Subagent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Enable_Subagent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Enable_Subagent() failed: ${response_json}"
        exit 4
    fi
}

Disable_Subagent()
{
    LogVerbose ".. Disable_Subagent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    
    if [ -n "${subagent_id}" ]
    then
        request_body="${request_body}, \"subagentIds\": ["
        comma=
        set -- "$(echo "${subagent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/subagents/disable"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/subagents/disable)    
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
                LogWarning "Disable_Subagent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Disable_Subagent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Disable_Subagent() failed: ${response_json}"
        exit 4
    fi
}

Reset_Subagent()
{
    LogVerbose ".. Reset_Subagent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    
    if [ -n "${subagent_id}" ]
    then
        request_body="${request_body}, \"subagentId\": \"${subagent_id}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/subagent/reset"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/subagent/reset)    
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
                LogWarning "Reset_Subagent() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Reset_Subagent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Reset_Subagent() failed: ${response_json}"
        exit 4
    fi
}

Version()
{
    LogVerbose ".. Version()"
    Curl_Options

    request_body="{"
    request_comma=

    if [ -n "${controller_id}" ]
    then
        request_body="${request_body}${request_comma} \"controllerIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${controller_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${agent_id}" ]
    then
        request_body="${request_body}${request_comma} \"agentIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/joc/versions"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/joc/versions)    
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.jocVersion // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Version() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Version() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Version() failed: ${response_json}"
        exit 4
    fi

    if [ "${list}" -eq 0 ]
    then
        if [ -n "${agent_id}" ]
        then
            version=$(echo "${response_json}" | jq -r '.agentVersions[0].version // empty')
        else
            if [ -n "${controller_id}" ]
            then
                version=$(echo "${response_json}" | jq -r '.controllerVersions[0].version // empty')
            else
                version=$(echo "${response_json}" | jq -r '.jocVersion // empty')
            fi
         fi
         
         Log "${version}"
    else
        Log "${response_json}"
    fi
}

Encrypt()
{
    in_string="$1"
    in_file="$2"

    java_options=(--cert="${cert_file}")

    if [ -n "${in_string}" ]
    then
        java_options+=(--in="${in_string}")
    fi

    if [ -n "${in_file}" ]
    then
        java_options+=(--infile="${in_file}")
    fi

    if [ -n "${outfile}" ]
    then
        java_options+=(--outfile="${outfile}")
    fi

    printf "enc:"
    "${JAVA}" -classpath "${java_lib}/patches/*:${java_lib}/sos/*:${java_lib}/3rd-party/*:${java_lib}/stdout" com.sos.commons.encryption.executable.Encrypt "${java_options[@]}"
}

Decrypt()
{
    in_string="$1"
    in_file="$2"

    java_options=(--key="${key_file}")

    if [ -n "${key_password}" ]
    then
        java_options+=(--key-password="${key_password}")
    fi

    if [ -n "${in_string}" ]
    then
        java_options+=(--in="${in_string}")
    fi

    if [ -n "${in_file}" ]
    then
        java_options+=(--infile="${in_file}")
    fi

    if [ -n "${outfile}" ]
    then
        java_options+=(--outfile="${outfile}")
    fi

    "${JAVA}" -classpath "${java_lib}/patches/*:${java_lib}/sos/*:${java_lib}/3rd-party/*:${java_lib}/stdout" com.sos.commons.encryption.executable.Decrypt "${java_options[@]}"
}

Usage()
{
    >&"$1" echo ""
    >&"$1" echo "Usage: $(basename "$0") [Command] [Options] [Switches]"
    >&"$1" echo ""
    >&"$1" echo "  Commands:"
    >&"$1" echo "    terminate           --controller-id [--controller-url] [--switch-over]"
    >&"$1" echo "    restart             --controller-id [--controller-url] [--switch-over]"
    >&"$1" echo "    cancel              --controller-id [--controller-url]"
    >&"$1" echo "    cancel-restart      --controller-id [--controller-url]"
    >&"$1" echo "    status              --controller-id [--controller-url]"
    >&"$1" echo "    version            [--controller-id] [--agent-id] [--list]"
    >&"$1" echo "    check               --controller-id  --controller-url"
    >&"$1" echo "    switch-over         --controller-id"
    >&"$1" echo "    appoint-nodes       --controller-id"
    >&"$1" echo "    confirm-loss        --controller-id"
    >&"$1" echo "    enable-agent        --controller-id --agent-id"
    >&"$1" echo "    disable-agent       --controller-id --agent-id"
    >&"$1" echo "    status-agent        --controller-id [--agent-id] [--state] [--no-hidden]"
    >&"$1" echo "    reset-agent         --controller-id --agent-id [--force]"
    >&"$1" echo "    switch-over-agent   --controller-id --agent-id"
    >&"$1" echo "    confirm-loss-agent  --controller-id --agent-id"
    >&"$1" echo "    enable-subagent     --controller-id --subagent-id"
    >&"$1" echo "    disable-subagent    --controller-id --subagent-id"
    >&"$1" echo "    reset-subagent      --controller-id --subagent-id [--force]"
    >&"$1" echo "    encrypt             --in [--infile --outfile] --cert [--java-home] [--java-lib]"
    >&"$1" echo "    decrypt             --in [--infile --outfile] --key [--key-password] [--java-home] [--java-lib]"
    >&"$1" echo ""
    >&"$1" echo "  Options:"
    >&"$1" echo "    --url=<url>                        | required: JOC Cockpit URL"
    >&"$1" echo "    --user=<account>                   | required: JOC Cockpit user account"
    >&"$1" echo "    --password=<password>              | optional: JOC Cockpit password"
    >&"$1" echo "    --ca-cert=<path>                   | optional: path to CA Certificate used for JOC Cockpit login"
    >&"$1" echo "    --client-cert=<path>               | optional: path to Client Certificate used for login"
    >&"$1" echo "    --client-key=<path>                | optional: path to Client Key used for login"
    >&"$1" echo "    --timeout=<seconds>                | optional: timeout for request, default: ${timeout}"
    >&"$1" echo "    --controller-id=<id>               | required: Controller ID"
    >&"$1" echo "    --controller-url=<url>             | optional: Controller URL for connection test"
    >&"$1" echo "    --agent-id=<id[,id]>               | optional: Agent IDs"
    >&"$1" echo "    --subagent-id=<id[,id]>            | optional: Subagent ID"
    >&"$1" echo "    --state=<state[,state]>            | optional: list of states for filtering Agents such as"
    >&"$1" echo "                                                   COUPLED, RESETTING, INITIALISED, COUPLINGFAILED, SHUTDOWN"
    >&"$1" echo "    --key=<path>                       | optional: path to private key file in PEM format"
    >&"$1" echo "    --key-password=<password>          | optional: password for private key file"
    >&"$1" echo "    --cert=<path>                      | optional: path to certificate file in PEM format"
    >&"$1" echo "    --in=<string>                      | optional: input string for encryption/decryption"
    >&"$1" echo "    --infile=<path>                    | optional: input file for encryption/decryption"
    >&"$1" echo "    --outfile=<path>                   | optional: output file for encryption/decryption"
    >&"$1" echo "    --java-home=<directory>            | optional: Java Home directory for encryption/decryption, default: ${JAVA_HOME}"
    >&"$1" echo "    --java-lib=<directory>             | optional: Java library directory for encryption/decryption, default: ${java_lib}"
    >&"$1" echo "    --audit-message=<string>           | optional: audit log message"
    >&"$1" echo "    --audit-time-spent=<number>        | optional: audit log time spent in minutes"
    >&"$1" echo "    --audit-link=<url>                 | optional: audit log link"
    >&"$1" echo "    --log-dir=<directory>              | optional: path to directory holding the script's log files"
    >&"$1" echo ""
    >&"$1" echo "  Switches:"
    >&"$1" echo "    -h | --help                        | displays usage"
    >&"$1" echo "    -v | --verbose                     | displays verbose output, repeat to increase verbosity"
    >&"$1" echo "    -p | --password                    | asks for password"
    >&"$1" echo "    -k | --key-password                | asks for key password"
    >&"$1" echo "    -l | --list                        | lists version information in JSON format"
    >&"$1" echo "    -o | --switch-over                 | switches over the active role to the standby instance"
    >&"$1" echo "    -f | --force                       | forces reset on Agent"
    >&"$1" echo "    --no-hidden                        | suppresses hidden Agents"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/-YZvCQ"
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
        terminate|restart|cancel|cancel-restart|status|version|check|switch-over|appoint-nodes|confirm-loss|enable-agent|disable-agent|status-agent|reset-agent|confirm-loss-agent|switch-over-agent|enable-subagent|disable-subagent|reset-subagent|encrypt|decrypt) action=$1
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
            --controller-url=*)     controller_url=$(echo "${option}" | sed 's/--controller-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --agent-id=*)           agent_id=$(echo "${option}" | sed 's/--agent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --subagent-id=*)        subagent_id=$(echo "${option}" | sed 's/--subagent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --state=*)              state=$(echo "${option}" | sed 's/--state=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --key=*)                key_file=$(echo "${option}" | sed 's/--key=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --cert=*)               cert_file=$(echo "${option}" | sed 's/--cert=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --key-password=*)       key_password=$(echo "${option}" | sed 's/--key-password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --in=*)                 in=$(echo "${option}" | sed 's/--in=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --infile=*)             infile=$(echo "${option}" | sed 's/--infile=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --outfile=*)            outfile=$(echo "${option}" | sed 's/--outfile=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --java-home=*)          java_home=$(echo "${option}" | sed 's/--java-home=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --java-lib=*)           java_lib=$(echo "${option}" | sed 's/--java-lib=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
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
                                    ;;
            -p|--password)          AskPassword
                                    ;;
            -k|--key-password)      AskKeyPassword
                                    ;;
            -l|--list)              list=1
                                    ;;
            -s|--switch-over)       switch_over=true
                                    ;;
            -f|--force)             force=true
                                    ;;
            --no-hidden)            no_hidden=true
                                    ;;
            --make-dirs)            make_dirs=1
                                    ;;
            --show-logs)            show_logs=1
                                    ;;
            terminate|restart|cancel|cancel-restart|status|version|check|switch-over|appoint-nodes|confirm-loss|enable-agent|disable-agent|status-agent|reset-agent|confirm-loss-agent|switch-over-agent|enable-subagent|disable-subagent|reset-subagent|encrypt|decrypt) action=$1
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

    actions="|encrypt|decrypt|"
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

    actions="|status|status-agent|check|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        if [ -z "${controller_id}" ]
        then
            Usage 2
            LogError "Controller ID must be specified: --controller-id="
            exit 1
        fi

        if [ "${action}" = "check" ] && [ -z "${controller_url}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify the Controller instance URL: --controller-url="
            exit 1
        fi
    fi

    actions="|enable-agent|disable-agent|reset-agent|confirm-loss-agent|switch-over-agent|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${agent_id}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify the Agent ID: --agent-id="
        exit 1
    fi

    actions="|enable-subagent|disable-subagent|reset-subagent|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${subagent_id}" ]
    then
        Usage 2
        LogError "Command '$action' requires to specify the Subagent ID: --subagent-id="
        exit 1
    fi

    actions="|encrypt|decrypt|"
    if [[ "${actions}" == *"|${action}|"* ]] || [[ "${joc_password}" == enc:* ]] || [[ "${key_password}" == enc:* ]]
    then
        if [ "${action}" = "encrypt" ] || [ "${action}" = "decrypt" ]
        then
            if [ -z "${in}" ] && [ -z "${infile}" ]
            then
                Usage 2
                LogError "Action '${action}' requires input string or input file to be specified: : --in= or --infile="
                exit 1
            fi
    
            if [ -n "${in}" ] && [ -n "${infile}" ]
            then
                Usage 2
                LogError "Action '${action}' requires one of input string or input file to be specified: : --in= or --infile="
                exit 1
            fi
        fi

        if [ "${action}" = "encrypt" ]
        then
            if [ -z "${cert_file}" ]
            then
                Usage 2
                LogError "Action '${action}' requires certificate file to be specified: --cert="
                exit 1
            fi

            if [ ! -f "${cert_file}" ]
            then
                Usage 2
                LogError "Certificate file not found: --cert=${cert_file}"
                exit 1
            fi
        fi

        if [ "${action}" = "decrypt" ]
        then
            if [ -z "${key_file}" ]
            then
                Usage 2
                LogError "Action '${action}' requires key file to be specified: --key="
                exit 1
            fi

            if [ ! -f "${key_file}" ]
            then
                Usage 2
                LogError "Key file not found: --key=${key_file}"
                exit 1
            fi
        fi

        if [ -z "${java_lib}" ]
        then
            Usage 2
            LogError "Action '${action}' requires Java encryption library directory to be specified: --java-lib="
            exit 1
        fi

        if [ ! -d "${java_lib}" ]
        then
            Usage 2
            LogError "Java encryption library directory not found: --java-lib=${java_lib}"
            exit 1
        fi

        if [ -n "${java_home}" ] && [ ! -d "${java_home}" ]
        then
            Usage 2
            LogError "Java Home directory not found: --java-home=${java_home}"
            exit 1
        fi
    
        if [ -n "${java_home}" ] && [ ! -f "${java_home}"/bin/java ]
        then
            Usage 2
            LogError "Java binary ./bin/java not found from Java Home directory: --java-home=${java_home}"
            exit 1
        fi
    
        JAVA="${JAVA_HOME}"/bin/
        if [ -n "${java_home}" ]
        then
            JAVA_HOME=${java_home}
            JAVA=${java_home}/bin/java
        else
            java_bin=$(which java 2>/dev/null || echo "")
            test -n "${JAVA_HOME}" && test -x "${JAVA_HOME}/bin/java" && java_bin="${JAVA_HOME}/bin/java"
            if [ -z "${java_bin}" ]
            then
                LogError "could not identify Java environment, please set JAVA_HOME variable"
                Usage 2
                exit 1
            fi
            
            JAVA=${java_bin}
        fi

        if [[ "${joc_password}" == enc:* ]]
        then
            joc_password=$(Decrypt "${joc_password}")
        fi

        if [[ "${key_password}" == enc:* ]]
        then
            key_password=$(Decrypt "${key_password}")
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
    
        log_file="${log_dir}"/operate-controller."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/operate-controller."${start_time}".log
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

    actions="|encrypt|decrypt|"
    if [[ "${actions}" != *"|${action}|"* ]]
    then
        Login
    fi

    case "${action}" in
        terminate)          Terminate_Controller
                            ;;
        restart)            Terminate_Restart_Controller
                            ;;
        cancel)             Cancel_Controller
                            ;;
        cancel-restart)     Cancel_Restart_Controller
                            ;;
        status)             Status_Controller
                            ;;
        version)            Version
                            ;;
        check)              Check_Controller
                            ;;
        switch-over)        Switchover_Controller
                            ;;
        appoint-nodes)      Appoint_Nodes_Controller
                            ;;
        confirm-loss)       Confirm_Node_Loss_Controller
                            ;;
        enable-agent)       Enable_Standalone_Agent
                            ;;
        disable-agent)      Disable_Standalone_Agent
                            ;;
        status-agent)       Status_Agent
                            ;;
        reset-agent)        Reset_Agent
                            ;;
        confirm-loss-agent) Confirm_Node_Loss_Agent
                            ;;
        switch-over-agent)  Switchover_Agent
                            ;;
        enable-subagent)    Enable_Subagent
                            ;;
        disable-subagent)   Disable_Subagent
                            ;;
        reset-subagent)     Reset_Subagent
                            ;;
        encrypt)            LogVerbose ".. Encrypt()"
                            LogVerbose ".... running: ${JAVA} -classpath ${java_lib}/patches/*:${java_lib}/sos/*:${java_lib}/3rd-party/*:${java_lib}/stdout com.sos.commons.encryption.executable.Encrypt"
                            Encrypt "${in}" "${infile}"
                            ;;
        decrypt)            LogVerbose ".. Decrypt()"
                            LogVerbose ".... running: ${JAVA} -classpath ${java_lib}/patches/*:${java_lib}/sos/*:${java_lib}/3rd-party/*:${java_lib}/stdout com.sos.commons.encryption.executable.Decrypt"
                            Decrypt "${in}" "${infile}"
                            ;;
    esac

    actions="|encrypt|decrypt|"
    if [[ "${actions}" != *"|${action}|"* ]]
    then
        Logout
    fi
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

    unset script_home
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
    unset controller_url
    unset agent_id
    unset subagent_id
    unset state
    unset switch_over
    unset force
    unset no_hidden
    unset version
    unset list

    unset cert_file
    unset key_file
    unset key_password
    unset in
    unset infile
    unset outfile
    unset java_home
    unset java_bin
    unset java_lib

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
