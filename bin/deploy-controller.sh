#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2024-08-24
# Purpose:  Deployment Operations on Workflows
# ------------------------------------------------------------
#
# Examples, see https://kb.sos-berlin.com/x/9YZvCQ:

# request_options=(--url=http://localhost:4446 --user=root --password=root)  
#
# register Standalone Controller
# ./deploy-controller.sh register ${request_options[@]} --primary-url=http://localhost:4444 --primary-title="Standalone Controller"
#
# store Standalone Agent
#./deploy-controller.sh store-agent ${request_options[@]} --controller-id=controller --agent-id=StandaloneAgent --agent-name=StandaloneAgent --agent-url="http://localhost:4445" --title="Standalone Agent"
#
# deploy Standalone Agent
# /deploy-controller.sh deploy-agent ${request_options[@]} --controller-id=controller --agent-id=StandaloneAgent

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

# Register_Controller()
primary_url=
primary_cluster_url=
primary_title=
secondary_url=
secondary_cluster_url=
secondary_title=

# Unregister_Controller()
# controller_id=

# Check_Controller()
controller_url=

# Export_Agent(), Import_Agent()
file=
format=ZIP
overwrite=false

# Store_Standalone_Agent()
agent_id=
agent_name=
title=
alias=
agent_url=
process_limit=0
hidden=false

# Deploy_Standalone_Agent()
# agent_id=
is_cluster=0

# Revoke_Standalone_Agent()
# agent_id=
# is_cluster=0

# Store_Cluster_Agent()
primary_subagent_id=
# primary_title=
# primary_url=
primary_own_cluster=false
secondary_subagent_id=
# secondary_title=
# secondary_url=
secondary_own_cluster=false

# Deploy_Cluster_Agent()
# agent_id=
# is_cluster=0

# Revoke_Cluster_Agent()
# agent_id=
# is_cluster=0

# Delete_Agent()
# agent_id=

# Store_Subagent()
# agent_id=
subagent_id=
subagent_url=
# title=
role=
subagent_own_cluster=false

# Delete_Subagent()
# subagent_id=

# Store_Subagent_Cluster()
# agent_id=
subagent_cluster_id=
# title=
# subagent_id=
subagent_cluster_priority=0

# Delete_Subagent_Cluster()
# subagent_cluster_id=

# Revoke_Subagent_Cluster()
# subagent_cluster_id=

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

Register_Controller()
{
    LogVerbose ".. Register_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"\", \"controllers\": ["
    request_comma=

    if [ -z "${secondary_url}" ]
    then
        controller_role=STANDALONE
    else
        controller_role=PRIMARY
    fi

    request_body="${request_body}${request_comma} { \"url\": \"${primary_url}\", \"clusterUrl\": \"${primary_cluster_url}\", \"role\": \"${controller_role}\", \"title\": \"${primary_title}\" }"
    request_comma=,

    if [ -n "${secondary_url}" ]
    then
        request_body="${request_body}${request_comma} { \"url\": \"${secondary_url}\", \"clusterUrl\": \"${secondary_cluster_url}\", \"role\": \"BACKUP\", \"title\": \"${secondary_title}\" }"
        request_comma=,
    fi

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/register"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/register)    
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
                LogWarning "Register_Controller() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Register_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Register_Controller() failed: ${response_json}"
        exit 4
    fi
}

Unregister_Controller()
{
    LogVerbose ".. Unegister_Controller()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/controller/unregister"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/controller/unregister)    
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
                LogWarning "Unegister_Controller() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Unegister_Controller() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Unegister_Controller() failed: ${response_json}"
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
                LogWarning "Check_Controller() could not find objects: ${response_json}"
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

Export_Agent()
{
    LogVerbose ".. Export_Agent()"
    Curl_Options

    request_body="{ \"exportFile\": { \"filename\": \"${file}\", \"format\": \"${format}\" }"
    
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
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" -H \"Content-Type: application/json\" -H \"Accept-Encoding: gzip, deflate\" -d ${request_body} -o ${file} ${joc_url}/joc/api/agents/export"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" -H "Content-Type: application/json" -H "Accept-Encoding: gzip, deflate" -d "${request_body}" -o "${file}" "${joc_url}"/joc/api/agents/export)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if [ ! -f "${file}" ]
    then
        LogWarning "Export_Agent() did not create export file: ${response_json}"
        exit 4
    else
        < "${file}" read -r -d '' -n 1 first_byte
        if [ "${first_byte}" = "{" ]
        then
            LogWarning "Export_Agent() reports error:"
            cat "${file}"
            exit 4
        fi
    fi
}

Import_Agent()
{
    LogVerbose ".. Import_Agent()"
    Curl_Options

    import_options=( -F "file=@${file}" -F "format=${format}" -F "controllerId=${controller_id}" -F "overwrite=${overwrite}")

    if [ -n "${audit_message}" ]
    then
        import_options+=(-F "comment=${audit_message}")

        if [ -n "${audit_time_spent}" ]
        then
            import_options+=(-F "timeSpent=${audit_time_spent}")
        fi

        if [ -n "${audit_link}" ]
        then
            import_options+=(-F "ticketLink=${audit_link}")
        fi
    fi

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" ${import_options[*]} ${joc_url}/joc/api/agents/import"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" "${import_options[@]}" "${joc_url}"/joc/api/agents/import)
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
                LogWarning "Import_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Import_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Import_Agent() failed: ${response_json}"
        exit 4
    fi
}

Store_Standalone_Agent()
{
    LogVerbose ".. Store_Standalone_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agents\": ["
    request_body="${request_body} { \"agentId\": \"${agent_id}\", \"agentName\": \"${agent_name}\", \"title\": \"${title}\", \"url\": \"${agent_url}\""
    
    if [ "${process_limit}" -gt 0 ]
    then
        request_body="${request_body}, \"processLimit\": ${process_limit}"
    fi
    
    request_body="${request_body}, \"hidden\": ${hidden}"

    if [ -n "${alias}" ]
    then
        request_body="${request_body}, \"agentNameAliases\": ["
        comma=
        set -- "$(echo "${alias}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body} } ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/store)
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
                LogWarning "Store_Standalone_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Standalone_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Standalone_Agent() failed: ${response_json}"
        exit 4
    fi
}

Store_Cluster_Agent()
{
    LogVerbose ".. Store_Cluster_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"clusterAgents\": ["
    request_body="${request_body} { \"agentId\": \"${agent_id}\", \"agentName\": \"${agent_name}\", \"title\": \"${title}\""
    
    if [ "${process_limit}" -gt 0 ]
    then
        request_body="${request_body}, \"processLimit\": ${process_limit}"
    fi

    if [ -n "${alias}" ]
    then
        request_body="${request_body}, \"agentNameAliases\": ["
        comma=
        set -- "$(echo "${alias}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"subagents\": ["
    request_comma=
    
    if [ -n "${primary_subagent_id}" ]
    then
        request_body="${request_body}${request_comma} { \"isDirector\": \"PRIMARY_DIRECTOR\", \"subagentId\": \"${primary_subagent_id}\", \"url\": \"${primary_url}\", \"title\": \"${primary_title}\", \"withGenerateSubagentCluster\": ${primary_own_cluster} }"
        request_comma=,
    fi

    if [ -n "${secondary_subagent_id}" ]
    then
        request_body="${request_body}${request_comma} { \"isDirector\": \"SECONDARY_DIRECTOR\", \"subagentId\": \"${secondary_subagent_id}\", \"url\": \"${secondary_url}\", \"title\": \"${secondary_title}\", \"withGenerateSubagentCluster\": ${secondary_own_cluster} }"
        request_comma=,
    fi

    request_body="${request_body} ] } ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/store)
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
                LogWarning "Store_Cluster_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Cluster_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Cluster_Agent() failed: ${response_json}"
        exit 4
    fi
}

Delete_Agent()
{
    LogVerbose ".. Delete_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentId\": \"${agent_id}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agent/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agent/delete)    
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
                LogWarning "Delete_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Agent() failed: ${response_json}"
        exit 4
    fi
}

Deploy_Standalone_Agent()
{
    LogVerbose ".. Deploy_Standalone_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentIds\": ["
    comma=
    set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/deploy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/deploy)    
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
                LogWarning "Deploy_Standalone_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Deploy_Standalone_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Deploy_Standalone_Agent() failed: ${response_json}"
        exit 4
    fi
}

Deploy_Cluster_Agent()
{
    LogVerbose ".. Deploy_Cluster_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"clusterAgentIds\": ["
    comma=
    set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/deploy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/deploy)    
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
                LogWarning "Deploy_Cluster_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Deploy_Cluster_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Deploy_Cluster_Agent() failed: ${response_json}"
        exit 4
    fi
}

Revoke_Standalone_Agent()
{
    LogVerbose ".. Revoke_Standalone_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentIds\": ["
    comma=
    set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/revoke"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/revoke)    
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
                LogWarning "Revoke_Standalone_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Revoke_Standalone_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Revoke_Standalone_Agent() failed: ${response_json}"
        exit 4
    fi
}

Revoke_Cluster_Agent()
{
    LogVerbose ".. Revoke_Cluster_Agent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"clusterAgentIds\": ["
    comma=
    set -- "$(echo "${agent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/revoke"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/revoke)    
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
                LogWarning "Revoke_Cluster_Agent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Revoke_Cluster_Agent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Revoke_Cluster_Agent() failed: ${response_json}"
        exit 4
    fi
}

Store_Subagent()
{
    LogVerbose ".. Store_Subagent()"
    Curl_Options

    subagent_role=NO_DIRECTOR
    
    if [ "${role}" = "primary" ]
    then
        subagent_role=PRIMARY_DIRECTOR
    else
        if [ "${role}" = "secondary" ]
        then
            subagent_role=SECONDARY_DIRECTOR
        fi
    fi

    request_body="{ \"controllerId\": \"${controller_id}\", \"agentId\": \"${agent_id}\""
    request_body="${request_body}, \"subagents\": [ { \"subagentId\": \"${subagent_id}\", \"url\": \"${subagent_url}\", \"title\": \"${title}\", \"isDirector\": \"${subagent_role}\", \"withGenerateSubagentCluster\": ${subagent_own_cluster} } ]"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/subagents/store"

    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/subagents/store)
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
                LogWarning "Store_Subagent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Subagent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Subagent() failed: ${response_json}"
        exit 4
    fi
}

Delete_Subagent()
{
    LogVerbose ".. Delete_Subagent()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"subagentIds\": ["
    comma=
    set -- "$(echo "${subagent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"${i}\""
        comma=,
    done
    request_body="${request_body} ]"
    
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/inventory/cluster/subagents/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/inventory/cluster/subagents/delete)    
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
                LogWarning "Delete_Subagent() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Subagent() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Subagent() failed: ${response_json}"
        exit 4
    fi
}

Store_Subagent_Cluster()
{
    LogVerbose ".. Store_Subagent_Cluster()"
    Curl_Options

    request_body="{ \"subagentClusters\": [ { \"agentId\": \"${agent_id}\", \"subagentClusterId\": \"${subagent_cluster_id}\", \"title\": \"${title}\""

    request_body="${request_body}, \"subagentIds\": ["
    item_priority=-1
    comma=
    set -- "$(echo "${subagent_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        if [ "${subagent_cluster_priority}" = "first" ]
        then
            item_priority=$((item_priority + 1))
        else
            if [ "${subagent_cluster_priority}" = "next" ]
            then
                item_priority=0
            fi
        fi
        request_body="${request_body}${comma} { \"subagentId\": \"${i}\", \"priority\": \"${item_priority}\" }"
        comma=,
    done
    request_body="${request_body} ]"

    request_body="${request_body} } ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/cluster/store"

    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/cluster/store)
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
                LogWarning "Store_Subagent_Cluster() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store_Subagent_Cluster() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store_Subagent_Cluster() failed: ${response_json}"
        exit 4
    fi
}

Delete_Subagent_Cluster()
{
    LogVerbose ".. Delete_Subagent_Cluster()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"subagentClusterIds\": ["

    comma=
    set -- "$(echo "${subagent_cluster_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"$i\""
        comma=,
    done

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/cluster/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/cluster/delete)    
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
                LogWarning "Delete_Subagent_Cluster() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Subagent_Cluster() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Subagent_Cluster() failed: ${response_json}"
        exit 4
    fi
}

Deploy_Subagent_Cluster()
{
    LogVerbose ".. Deploy_Subagent_Cluster()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"subagentClusterIds\": ["

    comma=
    set -- "$(echo "${subagent_cluster_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"$i\""
        comma=,
    done

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/cluster/deploy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/cluster/deploy)    
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
                LogWarning "Deploy_Subagent_Cluster() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Deploy_Subagent_Cluster() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Deploy_Subagent_Cluster() failed: ${response_json}"
        exit 4
    fi
}

Revoke_Subagent_Cluster()
{
    LogVerbose ".. Revoke_Subagent_Cluster()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\", \"subagentClusterIds\": ["

    comma=
    set -- "$(echo "${subagent_cluster_id}" | sed -r 's/[,]+/ /g')"
    for i in $@; do
        request_body="${request_body}${comma} \"$i\""
        comma=,
    done

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/agents/cluster/revoke"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/agents/cluster/revoke)    
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
                LogWarning "Revoke_Subagent_Cluster() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Revoke_Subagent_Cluster() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Revoke_Subagent_Cluster() failed: ${response_json}"
        exit 4
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
    >&"$1" echo "    register          --primary-url    [--primary-cluster-url]   [--primary-title]"
    >&"$1" echo "                     [--secondary-url] [--secondary-cluster-url] [--secondary-title]"
    >&"$1" echo "    unregister        --controller-id"
    >&"$1" echo "    check             --controller-id --controller-url"
    >&"$1" echo "    store-agent       --controller-id --agent-id --agent-name --agent-url [--title] [--alias] [--process-limit] [--hide]"
    >&"$1" echo "    ..                --controller-id --agent-id --agent-name [--title] [--alias] [--process-limit]"
    >&"$1" echo "                      --primary-subagent-id   --primary-url   [--primary-title]"
    >&"$1" echo "                      --secondary-subagent-id --secondary-url [--secondary-title]"
    >&"$1" echo "    delete-agent      --controller-id --agent-id"
    >&"$1" echo "    deploy-agent      --controller-id --agent-id [--cluster]"
    >&"$1" echo "    revoke-agent      --controller-id --agent-id [--cluster]"
    >&"$1" echo "    store-subagent    --controller-id --agent-id --subagent-id --subagent-url [--title] [--role]"
    >&"$1" echo "    delete-subagent   --controller-id --subagent-id"
    >&"$1" echo "    store-cluster     --controller-id --cluster-id --agent-id --subagent-id [--priority] [--title]"
    >&"$1" echo "    delete-cluster    --controller-id --cluster-id"
    >&"$1" echo "    deploy-cluster    --controller-id --cluster-id"
    >&"$1" echo "    revoke-cluster    --controller-id --cluster-id"
    >&"$1" echo "    export-agent      --controller-id --file [--format] --agent-id"
    >&"$1" echo "    import-agent      --controller-id --file [--format] [--overwrite]"
    >&"$1" echo "    encrypt           --in [--infile --outfile] --cert [--java-home] [--java-lib]"
    >&"$1" echo "    decrypt           --in [--infile --outfile] --key [--key-password] [--java-home] [--java-lib]"
    >&"$1" echo ""
    >&"$1" echo "  Options:"
    >&"$1" echo "    --url=<url>                        | required: JOC Cockpit URL"
    >&"$1" echo "    --user=<account>                   | required: JOC Cockpit user account"
    >&"$1" echo "    --password=<password>              | optional: JOC Cockpit password"
    >&"$1" echo "    --ca-cert=<path>                   | optional: path to CA Certificate used for JOC Cockpit login"
    >&"$1" echo "    --client-cert=<path>               | optional: path to Client Certificate used for login"
    >&"$1" echo "    --client-key=<path>                | optional: path to Client Key used for login"
    >&"$1" echo "    --timeout=<seconds>                | optional: timeout for request, default: ${timeout}"
    >&"$1" echo "    --controller-id=<id[,id]>          | required: Controller ID"
    >&"$1" echo "    --controller-url=<url>             | optional: Controller URL for connection test"
    >&"$1" echo "    --primary-url=<url>                | optional: Primary Controller/Director Agent URL"
    >&"$1" echo "    --primary-cluster-url=<url>        | optional: Primary Controller Cluster URL"
    >&"$1" echo "    --primary-title=<string>           | optional: Primary Controller/Director Agent title"
    >&"$1" echo "    --primary-subagent-id=<id>         | optional: Primary Director Agent Subagent ID"
    >&"$1" echo "    --secondary-url=<url>              | optional: Secondary Controller/Director Agent URL"
    >&"$1" echo "    --secondary-cluster-url=<url>      | optional: Secondary Controller Cluster URL"
    >&"$1" echo "    --secondary-title=<string>         | optional: Secondary Controller/Director Agent title"
    >&"$1" echo "    --secondary-subagent-id=<id>       | optional: Secondary Director Agent Subagent ID"
    >&"$1" echo "    --file=<path>                      | optional: path to export file or import file"
    >&"$1" echo "    --format=<ZIP|TAR_GZ>              | optional: format of export file or import file"
    >&"$1" echo "    --agent-id=<id[,id]>               | optional: Agent IDs"
    >&"$1" echo "    --agent-name=<name>                | optional: Agent name"
    >&"$1" echo "    --agent-url=<url>                  | optional: Agent URL"
    >&"$1" echo "    --title=<string>                   | optional: Agent title or Subagent Cluster title"
    >&"$1" echo "    --alias=<name[,name]>              | optional: Agent alias name"
    >&"$1" echo "    --process-limit=<number>           | optional: Agent max. number of parallel processes"
    >&"$1" echo "    --subagent-id=<id[,id]>            | optional: Subagent ID"
    >&"$1" echo "    --subagent-url=<url>               | optional: Subagent URL"
    >&"$1" echo "    --role=<primary|secondary|no>      | optional: Subagent role acting as Primary/Secondary Director Agent"
    >&"$1" echo "    --cluster-id=<id>                  | optional: Subagent Cluster ID"
    >&"$1" echo "    --priority=<first|next>            | optional: Subagent Cluster priority: active-passive, active-active"
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
    >&"$1" echo "    -o | --overwrite                   | overwrites objects on import"
    >&"$1" echo "    -i | --hide                        | hides Agent"
    >&"$1" echo "    -c | --cluster                     | specifies a Cluster Agent"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/9YZvCQ"
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
        register|unregister|check|store-agent|delete-agent|deploy-agent|revoke-agent|export-agent|import-agent|store-subagent|delete-subagent|store-cluster|delete-cluster|deploy-cluster|revoke-cluster|encrypt|decrypt) action=$1
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
            --primary-url=*)        primary_url=$(echo "${option}" | sed 's/--primary-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --primary-cluster-url=*) primary_cluster_url=$(echo "${option}" | sed 's/--primary-cluster-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --primary-title=*)      primary_title=$(echo "${option}" | sed 's/--primary-title=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --primary-subagent-id=*) primary_subagent_id=$(echo "${option}" | sed 's/--primary-subagent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --secondary-url=*)      secondary_url=$(echo "${option}" | sed 's/--secondary-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --secondary-cluster-url=*) secondary_cluster_url=$(echo "${option}" | sed 's/--secondary-cluster-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --secondary-title=*)    secondary_title=$(echo "${option}" | sed 's/--secondary-title=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --secondary-subagent-id=*) secondary_subagent_id=$(echo "${option}" | sed 's/--secondary-subagent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --file=*)               file=$(echo "${option}" | sed 's/--file=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --format=*)             format=$(echo "${option}" | sed 's/--format=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --agent-id=*)           agent_id=$(echo "${option}" | sed 's/--agent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --agent-name=*)         agent_name=$(echo "${option}" | sed 's/--agent-name=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --agent-url=*)          agent_url=$(echo "${option}" | sed 's/--agent-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --subagent-id=*)        subagent_id=$(echo "${option}" | sed 's/--subagent-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --subagent-url=*)       subagent_url=$(echo "${option}" | sed 's/--subagent-url=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --title=*)              title=$(echo "${option}" | sed 's/--title=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --alias=*)              alias=$(echo "${option}" | sed 's/--alias=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --process-limit=*)      process_limit=$(echo "${option}" | sed 's/--process-limit=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --role=*)               role=$(echo "${option}" | sed 's/--role=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --cluster-id=*)         subagent_cluster_id=$(echo "${option}" | sed 's/--cluster-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --priority=*)           subagent_cluster_priority=$(echo "${option}" | sed 's/--priority=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
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
            -c|--cluster)           is_cluster=1
                                    ;;
            -i|--hide)              hidden=true
                                    ;;
            -o|--overwrite)         overwrite=true
                                    ;;
            --make-dirs)            make_dirs=1
                                    ;;
            --show-logs)            show_logs=1
                                    ;;
            register|unregister|check|store-agent|delete-agent|deploy-agent|revoke-agent|export-agent|import-agent|store-subagent|delete-subagent|store-cluster|delete-cluster|deploy-cluster|revoke-cluster|encrypt|decrypt) action=$1
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

    actions="|unregister|store-agent|delete-agent|deploy-agent|revoke-agent|import-agent|store-subagent|delete-subagent|store-cluster|delete-cluster|deploy-cluster|revoke-cluster|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        if [ -z "${controller_id}" ]
        then
            Usage 2
            LogError "Controller ID must be specified: --controller-id="
            exit 1
        fi
    fi

    if [ "${action}" = "register" ] && [ -z "${primary_url}" ]
    then
        Usage 2
        LogError "Command 'register' requires to specify the Controller instance URL: --primary-url="
        exit 1
    fi

    if [ "${action}" = "check" ] && [ -z "${controller_url}" ]
    then
        Usage 2
        LogError "Command 'check' requires to specify the Controller instance URL: --controller-url="
        exit 1
    fi

    actions="|store-agent|delete-agent|deploy-agent|revoke-agent|store-subagent|store-cluster|export-agent|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${agent_id}" ]
    then
        Usage 2
        LogError "Command '${action}' requires to specify the Agent ID: --agent-id="
        exit 1
    fi

    if [ "${action}" = "store-agent" ] 
    then
        if [ -z "${agent_name}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Agent Name: --agent-name="
            exit 1
        fi

        if [ -z "${agent_url}" ] && [ -z "${primary_url}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Standalone Agent URL or the Director Agent URL: --agent-url, --primary-url="
            exit 1
        fi

        if [ -n "${primary_subagent_id}" ] &&  [ -z "${primary_url}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Subagent URL for a Primary Subagent ID: --primary-url="
            exit 1
        fi

        if [ -z "${primary_subagent_id}" ] &&  [ -n "${primary_url}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Subagent ID for a Primary Subagent URL: --primary-subagent-id="
            exit 1
        fi

        if [ -n "${secondary_subagent_id}" ] &&  [ -z "${secondary_url}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Subagent URL for a Secondary Subagent ID: --secondary-url="
            exit 1
        fi

        if [ -z "${primary_subagent_id}" ] &&  [ -n "${primary_url}" ]
        then
            Usage 2
            LogError "Command 'store-agent' requires to specify the Subagent ID for a Secondary Subagent URL: --secondary-subagent-id="
            exit 1
        fi
    fi

    if [ "${action}" = "store-subagent" ]
    then
        if [ -z "${subagent_id}" ]
        then
            Usage 2
            LogError "Command 'store-subagent' requires to specify the Subagent ID: --subagent-id="
            exit 1
        fi

        if [ -z "${subagent_url}" ]
        then
            Usage 2
            LogError "Command 'store-subagent' requires to specify the Subagent URL: --subagent-url="
            exit 1
        fi

        if [ -n "${role}" ] && [ ! "${role}" = "primary" ] && [ ! "${role}" = "secondary" ] && [ ! "${role}" = "no" ]
        then
            Usage 2
            LogError "Command 'store-subagent' using option --role allows the values 'primary', 'secondary', 'no': --role=${role}"
            exit 1
        fi
    fi

    if [ "${action}" = "delete-subagent" ] && [ -z "${subagent_id}" ]
    then
        Usage 2
        LogError "Command 'delete-subagent' requires to specify the Subagent ID: --subagent-id="
        exit 1
    fi

    actions="|store-cluster|delete-cluster|deploy-cluster|revoke-cluster|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${subagent_cluster_id}" ]
    then
        Usage 2
        LogError "Command '$action' requires to specify the Subagent Cluster ID: --cluster-id="
        exit 1
    fi

    if [ "${action}" = "store-cluster" ] && [ -z "${subagent_id}" ]
    then
        Usage 2
        LogError "Command 'store-cluster' requires to specify the Subagent ID: --subagent-id="
        exit 1
    fi

    if [ "${action}" = "store-cluster" ] && [ -n "${subagent_cluster_priority}" ]
    then
        if [ ! "${subagent_cluster_priority}" = "first" ] && [ ! "${subagent_cluster_priority}" = "next" ]
        then
            Usage 2
            LogError "Command 'store-cluster' requires to specify the priority from the values 'first' or 'next': --priority="
            exit 1
        fi
    fi

    actions="|export-agent|import-agent|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        if [ -z "${file}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify a file: --file="
            exit 1
        fi

        if [ "${action}" = "import-agent" ] && [ ! -f "${file}" ]
        then
            Usage 2
            LogError "File not found: --file=${file}"
            exit 1
        fi
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
    
        log_file="${log_dir}"/deploy-controller."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/deploy-controller."${start_time}".log
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
        register)           Register_Controller
                            ;;
        unregister)         Unregister_Controller
                            ;;
        check)              Check_Controller
                            ;;
        export-agent)       Export_Agent
                            ;;
        import-agent)       Import_Agent
                            ;;
        store-agent)        if [ -n "${agent_url}" ]
                            then
                                Store_Standalone_Agent
                            else
                                Store_Cluster_Agent
                            fi
                            ;;
        delete-agent)       Delete_Agent
                            ;;
        deploy-agent)       if [ "${is_cluster}" -eq 0 ]
                            then
                                Deploy_Standalone_Agent
                            else
                                Deploy_Cluster_Agent
                            fi
                            ;;
        revoke-agent)       if [ "${is_cluster}" -eq 0 ]
                            then
                                Revoke_Standalone_Agent
                            else
                                Revoke_Cluster_Agent
                            fi
                            ;;
        store-subagent)     Store_Subagent
                            ;;
        delete-subagent)    Delete_Subagent             
                            ;;
        store-cluster)      Store_Subagent_Cluster
                            ;;
        delete-cluster)     Delete_Subagent_Cluster             
                            ;;
        deploy-cluster)     Deploy_Subagent_Cluster             
                            ;;
        revoke-cluster)     Revoke_Subagent_Cluster             
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

    # Register_Controller()
    unset primary_url
    unset primary_cluster_url
    unset primary_title
    unset secondary_url
    unset secondary_cluster_url
    unset secondary_title

    # Check_Controller()
    unset controller_url

    # Export_Agent(), Import_Agent()
    unset file
    unset format
    unset overwrite

    # Store_Standalone_Agent()
    unset agent_id
    unset agent_name
    unset title
    unset alias
    unset agent_url
    unset process_limit
    unset hidden

    # Deploy_Standalone_Agent()
    # unset agent_id
    unset is_cluster

    # Revoke_Standalone_Agent()
    # unset agent_id
    # unset is_cluster

    # Store_Cluster_Agent()
    unset primary_subagent_id
    # unset primary_title
    # unset primary_url
    unset primary_own_cluster
    unset secondary_subagent_id
    # unset secondary_title
    # unset secondary_url
    unset secondary_own_cluster

    # Deploy_Cluster_Agent()
    # unset agent_id
    # unset is_cluster

    # Revoke_Cluster_Agent()
    # unset agent_id
    # unset is_cluster

    # Delete_Agent()
    # unset agent_id

    # Store_Subagent()
    # unset agent_id
    unset subagent_id
    # unset subagent_url
    # unset title
    unset role
    unset subagent_own_cluster

    # Delete_Subagent()
    # unset subagent_id

    # Store_Subagent_Cluster()
    # unset agent_id
    unset subagent_cluster_id
    # unset title
    # unset subagent_id
    unset subagent_cluster_priority

    # Delete_Subagent_Cluster()
    # unset subagent_cluster_id

    # Revoke_Subagent_Cluster()
    # unset subagent_cluster_id

    unset cert_file
    unset key_file
    unset key_password
    unset in
    unset infile
    unset outfile
    unset java_home
    unset java_bin
    unset java_lib

    # Audit Log
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
