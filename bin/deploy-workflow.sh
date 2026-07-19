#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2024-08-24
# Purpose:  Deployment Operations on Workflows
# ------------------------------------------------------------
#
# Examples:
# ./deploy-workflow.sh deploy --url=https://joc-2-0-primary.sos:7443 --user=root --password=root --controller-id=testsuite
#     --folder=/ap/Agent --recursive --date-from=now
#     deploys from folders recursively
#
# ./deploy-workflow.sh deploy --url=https://joc-2-0-primary.sos:7443 --user=root --password=root --controller-id=testsuite
#     --path=/ap/ap3jobs,/ap/apEnv --type=WORKFLOW --date-from=now
#     deploys workflows individually
#
# ./deploy-workflow.sh release --url=https://joc-2-0-primary.sos:7443 --user=root -p --controller-id=testsuite
#     --folder=/ap/Agent --recursive --date-from=now
#     releases from folders recursively
#
# ./deploy-workflow.sh release --url=https://joc-2-0-primary.sos:7443 --user=root --password=root --controller-id=testsuite
#     --path=/ap/Agent/apAgentSchedule01,/ap/Agent/apAgentSchedule02 --type=SCHEDULE --date-from=now
#     releases schedules individually


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

date_from=
folder=
start_folder=
recursive=false
for_signing=0
no_draft=false
no_deployed=false
no_released=false
no_invalid=false
use_short_path=false
object_path=
new_object_path=
deployable_object_types=WORKFLOW,FILEORDERSOURCE,JOBRESOURCE,NOTICEBOARD,LOCK
releasable_object_types=INCLUDESCRIPT,SCHEDULE,WORKINGDAYSCALENDAR,NONWORKINGDAYSCALENDAR,JOBTEMPLATE
file=
format=ZIP
overwrite=false
prefix=
suffix=
signature_algorithm=SHA512withECDSA
change=
no_referencing=0
no_references=0
version=

directory=.
keystore_file=
key_file=
cert_file=
key_password=
hash=sha256
temp_cert_file=
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

Compatiblity_Settings()
{
    LogVerbose ".. Compatiblity_Settings()"
    Curl_Options

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" ${joc_url}/joc/api/joc/version"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" "${joc_url}"/joc/api/joc/version)    
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        version=$(echo "${response_json}" | jq -r '.version // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${version}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Compatiblity_Settings() could not perform operation: ${response_json}"
                exit 3
            else
                LogError "Compatiblity_Settings() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Compatiblity_Settings() failed: ${response_json}"
        exit 4
    fi

    if [ "2.7.1" = "$(printf "%s\n%s" "2.7.1" "${version}" | sort -t '.' -k 1,1 -k 2,2 -k 3,3 | head -1)" ]
    then
        releasable_object_types=${releasable_object_types},REPORT
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

    request_body=$(echo "${changes_json}" | jq -c '{operationType: "EXPORT", configurations: [(.changes[].configurations[] | {name: .name, type: .objectType} )]}')
        
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/dependencies"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/dependencies)
LogVerbose ".... response:"
LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.requestedItems // empty' | sed 's/^"//' | sed 's/"$//')
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
            referencing_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.requestedItems[].referencedBy[] | select(.path | startswith('\"$folder/\"')) | {path: .path, name: .name, objectType: .objectType} )] }] }')
        else
            referencing_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.requestedItems[].referencedBy[] | {path: .path, name: .name, objectType: .objectType} )] }] }')
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
            referenced_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.requestedItems[].references[] | select(.path | startswith('\"$folder/\"')) | {path: .path, name: .name, objectType: .objectType} )] }] }')
        else
            referenced_json=$(echo "${response_json}" | jq -r "${jq_options}" '{changes: [ {configurations: [(.requestedItems[].references[] | {path: .path, name: .name, objectType: .objectType} )] }] }')
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

Export()
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

    LogVerbose ".. Export()"
    Curl_Options

    request_body="{ \"exportFile\": { \"filename\": \"${file}\", \"format\": \"${format}\" }, \"useShortPath\": ${use_short_path}, \"startFolder\": \"${start_folder}\""

    if [ "${for_signing}" -eq 1 ]
    then
        request_body="${request_body}, \"forSigning\": { \"controllerId\": \"${controller_id}\""
    else
        request_body="${request_body}, \"shallowCopy\": { \"controllerId\": \"${controller_id}\""
    fi

    # Deployables
    request_comma=
    
    if [[ "${deployable_object_types}" == *${object_type}* ]]
    then
        request_body="${request_body}, \"deployables\": {"

        if [ "${no_draft}" = "false" ]
        then
            if [ -n "${object_path}" ]
            then
                request_body="${request_body}${request_comma} \"draftConfigurations\": ["
                comma=
                set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
                for i in $@; do
                    request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                    comma=,
                done
                request_body="${request_body} ]"
            fi
    
            if [ -n "${folder}" ] && [ -z "${change}" ]
            then
                request_body="${request_body}${request_comma} \"draftConfigurations\": ["
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
                request_body=$(echo "${request_body}${request_comma} \"draftConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{draftConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$deployable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
            fi    

            request_comma=,
        fi
    
        if [ "${no_deployed}" = "false" ]
        then
        
            if [ -n "${object_path}" ]
            then
                request_body="${request_body}${request_comma} \"deployConfigurations\": ["
                comma=
                set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
                for i in $@; do
                    request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                    comma=,
                done
                request_body="${request_body} ]"
            fi
    
            if [ -n "${folder}" ] && [ -z "${changes_json}" ]
            then
                request_body="${request_body}${request_comma} \"deployConfigurations\": ["
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
                request_body=$(echo "${request_body}${request_comma} \"deployConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{deployConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$deployable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
            fi    

            request_comma=,
        fi

        request_body="${request_body} }"
    fi

    # Releasables
    request_comma=

    if [[ "${releasable_object_types}" == *${object_type}* ]] && [ "${for_signing}" -eq 0 ]
    then
        request_body="${request_body}, \"releasables\": {"
        request_comma=

        if [ "${no_draft}" = "false" ]
        then
            if [ -n "${object_path}" ]
            then
                request_body="${request_body}${request_comma} \"draftConfigurations\": ["
                comma=
                set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
                for i in $@; do
                    request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                    comma=,
                done
                request_body="${request_body} ]"
            fi
    
            if [ -n "${folder}" ] && [ -z "${changes_json}" ]
            then
                request_body="${request_body}${request_comma} \"draftConfigurations\": ["
                request_comma=,
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
                request_body=$(echo "${request_body}${request_comma} \"draftConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{draftConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$releasable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
            fi    

            request_comma=,
        fi

        if [ "${no_released}" = "false" ]
        then
            if [ -n "${object_path}" ]
            then
                request_body="${request_body}${request_comma} \"releasedConfigurations\": ["
                request_comma=,
                comma=
                set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
                for i in $@; do
                    request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                    comma=,
                done
                request_body="${request_body} ]"
            fi
    
            if [ -n "${folder}" ] && [ -z "${changes_json}" ]
            then
                request_body="${request_body}${request_comma} \"releasedConfigurations\": ["
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
                request_body=$(echo "${request_body}${request_comma} \"releasedConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{releasedConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$releasable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
            fi    

            request_comma=,
            request_body="${request_body}, \"withoutInvalid\": ${no_invalid}"
        fi

        request_body="${request_body} }"
    fi

    request_body="${request_body} } }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" -H \"Content-Type: application/json\" -H \"Accept-Encoding: gzip, deflate\" -d ${request_body} -o ${file} ${joc_url}/joc/api/inventory/export"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" -H "Content-Type: application/json" -H "Accept-Encoding: gzip, deflate" -d "${request_body}" -o "${file}" "${joc_url}"/joc/api/inventory/export)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if [ ! -f "${file}" ]
    then
        LogWarning "Export() did not create export file: ${response_json}"
        exit 4
    else
        < "${file}" read -r -d '' -n 1 first_byte
        if [ "${first_byte}" = "{" ]
        then
            LogWarning "Export() reports error:"
            cat "${file}"
            exit 4
        fi
    fi
}

Export_Folder()
{
    LogVerbose ".. Export_Folder()"
    Curl_Options

    request_body="{ \"exportFile\": { \"filename\": \"${file}\", \"format\": \"${format}\" }, \"useShortPath\": ${use_short_path}"

    if [ "${for_signing}" -eq 1 ]
    then
        request_body="${request_body}, \"forSigning\": {"
    else
        request_body="${request_body}, \"shallowCopy\": {"
    fi

    request_body="${request_body} \"controllerId\": \"${controller_id}\""
    
    if [ -n "${object_type}" ]
    then
        request_body="${request_body}, \"objectTypes\": ["
        comma=
        set -- "$(echo "${object_type}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    else
        request_body="${request_body}, \"objectTypes\": ["
        comma=
        set -- "$(echo "${deployable_object_types},${releasable_object_types}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${folder}" ]
    then
        request_body="${request_body}, \"folders\": ["
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"recursive\": ${recursive}"
    request_body="${request_body}, \"withoutDrafts\": ${no_draft}"
    request_body="${request_body}, \"withoutDeployed\": ${no_deployed}"
    request_body="${request_body}, \"withoutReleased\": ${no_released}"

    if [ "${for_signing}" -eq 0 ]
    then
        request_body="${request_body}, \"onlyValidObjects\": ${no_invalid}"
    fi

    request_body="${request_body} }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" -H \"Content-Type: application/json\" -H \"Accept-Encoding: gzip, deflate\" -d ${request_body}  -o ${file} ${joc_url}/joc/api/inventory/export/folder"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" -H "Content-Type: application/json" -H "Accept-Encoding: gzip, deflate" -d "${request_body}" -o "${file}" "${joc_url}"/joc/api/inventory/export/folder)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if [ ! -f "${file}" ]
    then
        LogWarning "Export_Folder() did not create export file: ${response_json}"
        exit 4
    else
        < "${file}" read -r -d '' -n 1 first_byte
        if [ "${first_byte}" = "{" ]
        then
            LogWarning "Export_Folder() reports error:"
            cat "${file}"
            exit 4
        fi
    fi
}

Import()
{
    LogVerbose ".. Import()"
    Curl_Options

    if [ -n "${folder}" ]
    then
        target_folder="${folder}"
    else
        target_folder=/
    fi

    import_options=( -F "file=@${file}" -F "format=${format}" -F "targetFolder=${target_folder}" -F "overwrite=${overwrite}")

    if [ -n "${prefix}" ]
    then
        import_options+=(-F "prefix=${prefix}")
    fi

    if [ -n "${suffix}" ]
    then
        import_options+=(-F "suffix=${suffix}")
    fi

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

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" ${import_options[*]} ${joc_url}/joc/api/inventory/import"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" "${import_options[@]}" "${joc_url}"/joc/api/inventory/import)
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
                LogWarning "Import() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Import() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Import() failed: ${response_json}"
        exit 4
    fi
}

Import_Deploy()
{
    LogVerbose ".. Import_Deploy()"
    Curl_Options

    if [ -n "${folder}" ]
    then
        target_folder="${folder}"
    else
        target_folder=/
    fi

    import_options=( -F "file=@${file}" -F "format=${format}" -F "targetFolder=${target_folder}" -F "controllerId=${controller_id}" -F "signatureAlgorithm=${signature_algorithm}")

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

    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: */*\" ${import_options[*]} ${joc_url}/joc/api/inventory/deployment/import_deploy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: */*" "${import_options[@]}" "${joc_url}"/joc/api/inventory/deployment/import_deploy)
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
                LogWarning "Import_Deploy() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Import_Deploy() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Import_Deploy() failed: ${response_json}"
        exit 4
    fi
}

Deploy()
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

    LogVerbose ".. Deploy()"
    Curl_Options

    request_body="{"
    request_comma=

    if [ -n "${controller_id}" ]
    then
        request_body="${request_body} \"controllerIds\": ["
        comma=
        set -- "$(echo "${controller_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
        request_comma=,
    fi
    
    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"addOrdersDateFrom\": \"${date_from}\""
        request_comma=,
    fi

    request_body="${request_body}${request_comma} \"store\": {"
    request_comma=

    if [ "${no_draft}" = "false" ]
    then
        if [ -n "${object_path}" ]
        then
            request_body="${request_body}${request_comma} \"draftConfigurations\": ["
            comma=
            set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                comma=,
            done
            request_body="${request_body} ]"
        fi

        if [ -n "${folder}" ] && [ -z "${change}" ]
        then
            request_body="${request_body}${request_comma} \"draftConfigurations\": ["
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
            request_body=$(echo "${request_body}${request_comma} \"draftConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{draftConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$deployable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
        fi    

        request_comma=,
    fi

    if [ "${no_deployed}" = "false" ]
    then
        if [ -n "${object_path}" ]
        then
            request_body="${request_body}${request_comma} \"deployConfigurations\": ["
            comma=
            set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
                comma=,
            done
            request_body="${request_body} ]"
        fi

        if [ -n "${folder}" ] && [ -z "${change}" ]
        then
            request_body="${request_body}${request_comma} \"deployConfigurations\": ["
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
            request_body=$(echo "${request_body}${request_comma} \"deployConfigurations\":")$(echo "${changes_json}" | jq "${jq_options}" '{deployConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$deployable_object_types\"')) | { configuration: {path: .path, objectType: .objectType} } )]} | .[]')
        fi    

        request_comma=,
    fi

    request_body="${request_body} }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/deployment/deploy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/deployment/deploy)
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
                LogWarning "Deploy() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Deploy() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Deploy() failed: ${response_json}"
        exit 4
    fi
}

Revoke()
{
    LogVerbose ".. Revoke()"
    Curl_Options

    request_body="{"

    if [ -n "${controller_id}" ]
    then
        request_body="${request_body} \"controllerIds\": ["
        comma=
        set -- "$(echo "${controller_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi
    
    request_body="${request_body}, \"deployConfigurations\": ["

    if [ -n "${folder}" ]
    then
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"FOLDER\", \"recursive\": ${recursive} } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${object_path}" ]
    then
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"configuration\": { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} } }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body} }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/deployment/revoke"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/deployment/revoke)
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
                LogWarning "Revoke() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Revoke() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Revoke() failed: ${response_json}"
        exit 4
    fi
}

Release()
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

    LogVerbose ".. Release()"
    Curl_Options

    request_body="{"
    request_comma=

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"addOrdersDateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${object_path}" ]
    then
        request_body="${request_body}${request_comma} \"update\": ["
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"path\": \"${i}\", \"objectType\": \"${object_type}\", \"recursive\": ${recursive} }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${folder}" ] && [ -z "${change}" ]
    then
        request_body="${request_body}${request_comma} \"update\": ["
        comma=
        set -- "$(echo "${folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"path\": \"${i}\", \"objectType\": \"FOLDER\", \"recursive\": ${recursive} }"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${change}" ] && [ -n "${changes_json}" ]
    then
        request_body=$(echo "${request_body} \"update\":")$(echo "${changes_json}" | jq "${jq_options}" '{deployConfigurations: [(.changes[].configurations[] | select(.objectType | inside('\"$releasable_object_types\"')) | {path: .path, objectType: .objectType} )]} | .[]')
    fi    

    #request_body="${request_body} }"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/release"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/release)
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
                LogWarning "Release() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Release() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Release() failed: ${response_json}"
        exit 4
    fi
}

Recall()
{
    LogVerbose ".. Recall()"
    Curl_Options

    request_body="{ \"releasables\": ["

    if [ -n "${object_path}" ]
    then
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"path\": \"${i}\", \"objectType\": \"${object_type}\" }"
            comma=,
        done
    fi

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/releasables/recall"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/releasables/recall)
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
                LogWarning "Recall() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Recall() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Recall() failed: ${response_json}"
        exit 4
    fi
}

Recall_Folder()
{
    LogVerbose ".. Recall_Folder()"
    Curl_Options

    request_body="{ "

    if [ -n "${folder}" ]
    then
        request_body="${request_body} \"path\": \"${folder}\""
    fi

    if [ -n "${object_type}" ]
    then
        comma=
        request_body="${request_body}, \"objectTypes\": ["
        set -- "$(echo "${object_type}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma}\"$i\""
            comma=,
        done
        request_body="${request_body}]"
    fi

    request_body="${request_body}, \"recursive\": ${recursive}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/releasables/recall/folder"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/releasables/recall/folder)
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
                LogWarning "Recall_Folder() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Recall_Folder() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Recall_Folder() failed: ${response_json}"
        exit 4
    fi
}

Store()
{
    LogVerbose ".. Store()"
    Curl_Options

    request_body="{ \"path\": \"${object_path}\", \"objectType\": \"${object_type}\", \"configuration\": "$(< "${file}")
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/store"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/store)
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
                LogWarning "Store() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Store() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Store() failed: ${response_json}"
        exit 4
    fi
}

Get_Path()
{
    name=$1

    LogVerbose ".. Get_Path(): ${name}"
    Curl_Options

    if [ "${no_draft}" = "true" ]
    then
        use_drafts=false
    else
        use_drafts=true
    fi

    request_body="{ \"name\": \"$name\", \"objectType\": \"${object_type}\", \"useDrafts\": ${use_drafts}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/path"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/path)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        path=$(echo "${response_json}" | jq -r '.path // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${path}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Path() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Path() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Get_Path() failed: ${response_json}"
        exit 4
    fi
    
    echo "${path}"
}

Revalidate_Folder()
{
    LogVerbose ".. Revalidate_Folder()"
    Curl_Options

    request_body="{ \"path\": \"${folder}\", \"recursive\": ${recursive}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/revalidate/folder"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/revalidate/folder)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.validObjs // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Revalidate_Folder() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Revalidate_Folder() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Revalidate_Folder() failed: ${response_json}"
        exit 4
    fi
}

Remove()
{
    LogVerbose ".. Remove()"
    Curl_Options

    request_body="{ \"objects\": ["

    if [ -n "${object_path}" ]
    then
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"path\": \"${i}\", \"objectType\": \"${object_type}\" }"
            comma=,
        done
    fi

    request_body="${request_body} ]"

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}, \"addOrdersDateFrom\": \"${date_from}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/remove"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/remove)
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
                LogWarning "Remove() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Remove() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove() failed: ${response_json}"
        exit 4
    fi
}

Remove_Folder()
{
    LogVerbose ".. Remove_Folder()"
    Curl_Options

    request_body="{ \"path\": \"${folder}\""

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}, \"cancelOrdersDateFrom\": \"${date_from}\""
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/remove/folder"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/remove/folder)
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
                LogWarning "Remove_Folder() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Remove_Folder() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Remove_Folder() failed: ${response_json}"
        exit 4
    fi
}

Restore()
{
    LogVerbose ".. Restore()"
    Curl_Options

    if [ -n "${folder}" ]
    then
        request_body="{ \"path\": \"${folder}\", \"objectType\": \"FOLDER\""
    else
        request_body="{ \"path\": \"${object_path}\", \"objectType\": \"${object_type}\""
    fi
    
    request_body="${request_body}, \"newPath\": \"${new_object_path}\", \"suffix\": \"${suffix}\", \"prefix\": \"${prefix}\""
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/trash/restore"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/trash/restore)
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
                LogWarning "Restore() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Restore() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Restore() failed: ${response_json}"
        exit 4
    fi
}

Delete()
{
    LogVerbose ".. Delete()"
    Curl_Options

    request_body="{ \"objects\": ["

    if [ -n "${object_path}" ]
    then
        comma=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} { \"path\": \"${i}\", \"objectType\": \"${object_type}\" }"
            comma=,
        done
    fi

    request_body="${request_body} ]"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/trash/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/trash/delete)
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
                LogWarning "Delete() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete() failed: ${response_json}"
        exit 4
    fi
}

Delete_Folder()
{
    LogVerbose ".. Delete_Folder()"
    Curl_Options

    request_body="{ \"path\": \"${folder}\""

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/inventory/trash/delete/folder"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/inventory/trash/delete/folder)
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
                LogWarning "Delete_Folder() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Folder() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Folder() failed: ${response_json}"
        exit 4
    fi
}

Sign_Workflow()
{
    sign_file=$1
    sign_hash=$2

    Log ".. Sign_Workflow()"
    LogVerbose ".... signing file: ${sign_file} using algorithm ${sign_hash}"

    # step 1: create signature from file
    if [ -n "${key_file}" ]
    then
       openssl dgst -r -"${sign_hash}" -sign "${key_file}" -passin pass:"${key_password}" -out "${sign_file}".sig.bin "${sign_file}"
    else
       openssl dgst -r -"${sign_hash}" -sign "${keystore_file}" -keyform P12 -passin pass:"${key_password}" -out "${sign_file}".sig.bin "${sign_file}"
    fi

    # step 2: convert signature to base64
    base64 "${sign_file}".sig.bin > "${sign_file}".sig

    # step 3: prepare certificate file
    if [ -z "${cert_file}" ]
    then
        temp_cert_file=/tmp/deploy-workflow-$$.crt
        cert_file="${temp_cert_file}"

        if [ -n "${key_file}" ]
        then
            openssl pkcs12 -in "${key_file}" -passin pass:"${key_password}" -passout pass:"${key_password}" -nokeys -out "${temp_cert_file}" 2> /dev/null
        else
            openssl pkcs12 -in "${keystore_file}" -passin pass:"${key_password}" -passout pass:"${key_password}" -nokeys -out "${temp_cert_file}" 2> /dev/null
        fi
    fi

    # step 4: verify signature from public key
    openssl x509 -in "${cert_file}" -pubkey -noout > "${cert_file}".pub
    Log "$(openssl dgst -"${sign_hash}" -verify "${cert_file}".pub -signature "${sign_file}".sig.bin "${sign_file}")"
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
    >&"$1" echo "    export            --file [--format] --path --type [--use-short-path] [--start-folder] [--for-signing]"
    >&"$1" echo "    ..                --file [--format] --folder [--recursive] [--type] [--use-short-path] [--for-signing]"
    >&"$1" echo "                             [--no-draft] [--no-deployed] [--no-released] [--no-invalid]"
    >&"$1" echo "                             [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    import            --file [--format] [--folder] [--overwrite] [--prefix] [--suffix]"
    >&"$1" echo "    import-deploy     --file [--format] [--folder] [--algorithm]"
    >&"$1" echo "    deploy            --path --type [--date-from] [--no-draft] [--no-deployed]"
    >&"$1" echo "    ..                --folder [--recursive] [--date-from] [--no-draft] [--no-deployed]"
    >&"$1" echo "                               [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    revoke            --path --type"
    >&"$1" echo "    ..                --folder [--recursive]"
    >&"$1" echo "    release           --path --type [--date-from]"
    >&"$1" echo "    ..                --folder [--recursive] [--date-from]"
    >&"$1" echo "                               [--change] [--no-referencing] [--no-references]"
    >&"$1" echo "    recall            --path --type"
    >&"$1" echo "    ..                --folder [--recursive] [--type]"
    >&"$1" echo "    store             --path --type --file"
    >&"$1" echo "    remove            --path --type [--date-from]"
    >&"$1" echo "    ..                --folder [--date-from]"
    >&"$1" echo "    restore           --path --type --new-path [--prefix] [--suffix]"
    >&"$1" echo "    ..                --folder --new-path [--prefix] [--suffix]"
    >&"$1" echo "    delete            --path --type"
    >&"$1" echo "    ..                --folder"
    >&"$1" echo "    revalidate        --folder [--recursive]"
    >&"$1" echo "    sign              --file      [--keystore|--key --cert] [--key-password] [--hash]"
    >&"$1" echo "    ..                --directory [--keystore|--key --cert] [--key-password] [--hash]"
    >&"$1" echo "    encrypt           --in [--infile --outfile] --cert [--java-home] [--java-lib]"
    >&"$1" echo "    decrypt           --in [--infile --outfile] --key [--key-password] [--java-home] [--java-lib]"
    >&"$1" echo ""
    >&"$1" echo "  Options:"
    >&"$1" echo "    --url=<url>                        | required: JOC Cockpit URL"
    >&"$1" echo "    --controller-id=<id[,id]>          | required: Controller ID"
    >&"$1" echo "    --user=<account>                   | required: JOC Cockpit user account"
    >&"$1" echo "    --password=<password>              | optional: JOC Cockpit password"
    >&"$1" echo "    --ca-cert=<path>                   | optional: path to CA Certificate used for JOC Cockpit login"
    >&"$1" echo "    --client-cert=<path>               | optional: path to Client Certificate used for login"
    >&"$1" echo "    --client-key=<path>                | optional: path to Client Key used for login"
    >&"$1" echo "    --timeout=<seconds>                | optional: timeout for request, default: ${timeout}"
    >&"$1" echo "    --file=<path>                      | optional: path to export file or import file"
    >&"$1" echo "    --format=<ZIP|TAR_GZ>              | optional: format of export file or import file"
    >&"$1" echo "    --folder=<folder[,folder]>         | optional: list of inventory folders holding objects"
    >&"$1" echo "    --start-folder=<folder>            | optional: start folder for export with relative paths"
    >&"$1" echo "    --path=<path[,path]>               | optional: list of inventory paths to objects"
    >&"$1" echo "    --type=<type[,type]>               | optional: list of object types such as WORKFLOW,SCHEDULE"
    >&"$1" echo "    --new-path=<path>                  | optional: new object path on restore"
    >&"$1" echo "    --change=<change[,change]>         | optional: inventory changes of objects"
    >&"$1" echo "    --prefix=<string>                  | optional: prefix for duplicate objects on import"
    >&"$1" echo "    --suffix=<string>                  | optional: suffix for duplicate objects on import"
    >&"$1" echo "    --algorithm=<identifier>           | optional: signature algorithm for import, default: SHA512withECDSA"
    >&"$1" echo "    --date-from=<date>                 | optional: update daily plan start date for deploy/release operation"
    >&"$1" echo "    --directory=<directory>            | optional: path to directory with files that should be signed"
    >&"$1" echo "    --keystore=<path>                  | optional: path to keystore file in PKCS12 format"
    >&"$1" echo "    --key=<path>                       | optional: path to private key file in PEM format"
    >&"$1" echo "    --key-password=<password>          | optional: password for keystore/private key file"
    >&"$1" echo "    --cert=<path>                      | optional: path to certificate file in PEM format"
    >&"$1" echo "    --hash=<sha256|sha512>             | optional: hash algorithm for signing such as sha256, sha512, default: ${hash}"
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
    >&"$1" echo "    -k | --key-password                | asks for keystore/key password"
    >&"$1" echo "    -r | --recursive                   | specifies folders to be looked up recursively"
    >&"$1" echo "    -o | --overwrite                   | overwrites objects on import"
    >&"$1" echo "    -s | --for-signing                 | exports objects for digital signing"
    >&"$1" echo "    -u | --use-short-path              | exports relative paths"
    >&"$1" echo "    --no-referencing                   | excludes referencing objects when used with --change"
    >&"$1" echo "    --no-references                    | excludes referenced objects when used with --change"
    >&"$1" echo "    --no-draft                         | excludes draft objects"
    >&"$1" echo "    --no-deployed                      | excludes deployed objects"
    >&"$1" echo "    --no-released                      | excludes released objects"
    >&"$1" echo "    --no-invalid                       | excludes invalid objects"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/n4NvCQ"
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
        export|import|import-deploy|deploy|revoke|release|recall|store|revalidate|remove|restore|delete|sign|encrypt|decrypt) action=$1
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
            --file=*)               file=$(echo "${option}" | sed 's/--file=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --format=*)             format=$(echo "${option}" | sed 's/--format=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --path=*)               object_path=$(echo "${option}" | sed 's/--path=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --new-path=*)           new_object_path=$(echo "${option}" | sed 's/--new-path=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --folder=*)             folder=$(echo "${option}" | sed 's/--folder=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --start-folder=*)       start_folder=$(echo "${option}" | sed 's/--start-folder=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --type=*)               object_type=$(echo "${option}" | sed 's/--type=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --change=*)             change=$(echo "${option}" | sed 's/--change=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --prefix=*)             prefix=$(echo "${option}" | sed 's/--prefix=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --suffix=*)             suffix=$(echo "${option}" | sed 's/--suffix=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --algorithm=*)          signature_algorithm=$(echo "${option}" | sed 's/--algorithm=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --date-from=*)          date_from=$(echo "${option}" | sed 's/--date-from=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --directory=*)          directory=$(echo "${option}" | sed 's/--directory=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --keystore=*)           keystore_file=$(echo "${option}" | sed 's/--keystore=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --key=*)                key_file=$(echo "${option}" | sed 's/--key=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --cert=*)               cert_file=$(echo "${option}" | sed 's/--cert=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --key-password=*)       key_password=$(echo "${option}" | sed 's/--key-password=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --hash=*)               hash=$(echo "${option}" | sed 's/--hash=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
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
                                    jq_options=-M
                                    ;;
            -p|--password)          AskPassword
                                    ;;
            -k|--key-password)      AskKeyPassword
                                    ;;
            -r|--recursive)         recursive=true
                                    ;;
            -o|--overwrite)         overwrite=true
                                    ;;
            -s|--for-signing)       for_signing=1
                                    ;;
            -u|--use-short-path)    use_short_path=true
                                    ;;
            --no-draft)             no_draft=true
                                    ;;
            --no-deployed)          no_deployed=true
                                    ;;
            --no-released)          no_released=true
                                    ;;
            --no-invalid)           no_invalid=true
                                    ;;
            --no-referencing)       no_referencing=1
                                    ;;
            --no-references)        no_references=1
                                    ;;
            --make-dirs)            make_dirs=1
                                    ;;
            --show-logs)            show_logs=1
                                    ;;
            export|import|import-deploy|deploy|revoke|release|recall|store|revalidate|remove|restore|delete|sign|encrypt|decrypt)
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

    actions="|sign|encrypt|decrypt|"
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

    if [ "${action}" = "export" ] || [ "${action}" = "import" ] || [ "${action}" = "import-deploy" ] || [ "${action}" = "store" ]
    then
        if [ -z "${file}" ]
        then
            Usage 2
            LogError "Command '${action}' requires to specify a file: --file="
            exit 1
        fi
    fi

    if [ "${action}" = "store" ] && [ -n "${file}" ] && [ ! -f "${file}" ]
    then
        Usage 2
        LogError "File not found: --file=${file}"
        exit 1
    fi

    if [ "${action}" = "store" ] && [ -z "${object_path}" ]
    then
        Usage 2
        LogError "Command 'store' requires to specify a path: --path="
        exit 1
    fi

    if [ "${action}" = "revalidate" ] && [ -z "${folder}" ]
    then
        Usage 2
        LogError "Command 'revalidate' requires to specify a folder: --folder="
        exit 1
    fi

    actions="|import|import-deploy|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ "${overwrite}" = "true" ]
    then
        if [ -n "${prefix}" ] || [ -n "${suffix}" ]
        then
            Usage 2
            LogError "Command '${action}' using --overwrite denies to specify --prefix or --suffix"
            exit 1
        fi
    fi

    actions="|export|deploy|revoke|release|recall|remove|restore|delete|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -n "${folder}" ] && [ -n "${object_path}" ]
    then
        Usage 2
        LogError "Command '${action}' allows only one of the options: --folder, --path"
        exit 1
    fi

    actions="|export|deploy|revoke|release|recall|remove|restore|delete|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${folder}" ] && [ -z "${object_path}" ]
    then
        if [ "${action}" = "export" ] || [ "${action}" = "deploy" ] || [ "${action}" = "release" ]
        then
            if [ -z "${change}" ]
            then
                Usage 2
                LogError "Command '${action}' requires to specify one of the options: --folder=, --path=, --change="
                exit 1        
            else
                if [ "${no_draft}" = "true" ] || [ "${no_deployed}" = "true" ] || [ "${no_released}" = "true" ] || [ "${no_invalid}" = "true" ]
                then
                    Usage 2
                    LogError "Command '${action}' used with the --change option denies use of the switches: --no-draft, --no-deployed, --no-released, --no-invalid"
                exit 1        
                fi
            fi
        else
            Usage 2
            LogError "Command '${action}' requires to specify one of the options: --folder=, --path="
            exit 1
        fi
    fi

    actions="|export|deploy|revoke|release|recall|store|remove|restore|delete|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -n "${object_path}" ] && [ -z "${object_type}" ]
    then
        Usage 2
        LogError "Command '${action}' using --path option requires to specify the object type: --type="
        exit 1
    fi

    actions="|sign|"
    if [[ "${actions}" == *"|${action}|"* ]]
    then
        if [ -z "${directory}" ] && [ -z "${file}" ]
        then
            Usage 2
            LogError "Action '${action}' requires one of a directory holding files or a file to be specified for signing: --directory= or --file="
            exit 1
        fi
    
        if [ -n "${directory}" ] && [ -n "${file}" ]
        then
            if [ "${directory}" = '.' ]
            then
                directory=
            else
                Usage 2
                LogError "Action '${action}' requires one of a directory holding files or a file to be specified for signing: --directory= or --file="
                exit 1
            fi
        fi

        if [ -z "${key_file}" ] && [ -z "${keystore_file}" ]
        then
            Usage 2
            LogError "Action '${action}' requires one of a keystore file or key file to be specified: --keystore= or --key="
            exit 1
        fi
    
        if [ -n "${key_file}" ] && [ -n "${keystore_file}" ]
        then
            Usage 2
            LogError "Action '${action}' requires one of a keystore file or key file to be specified: --keystore= or --key="
            exit 1
        fi
    
        if [ -z "${cert_file}" ] && [ -z "${keystore_file}" ]
        then
            Usage 2
            LogError "Action '${action}' requires one of a keystore file or certificate file to be specified: --keystore= or --cert="
            exit 1
        fi
    
        if [ -n "${keystore_file}" ] && [ ! -f "${keystore_file}" ]
        then
            Usage 2
            LogError "Keystore file not found: --keystore=${keystore_file}"
            exit 1
        fi
    
        if [ -n "${key_file}" ] && [ ! -f "${key_file}" ]
        then
            Usage 2
            LogError "Key file not found: --key=${key_file}"
            exit 1
        fi
    
        if [ -n "${cert_file}" ] && [ ! -f "${cert_file}" ]
        then
            Usage 2
            LogError "Certificate file not found: --cert=${cert_file}"
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
    
        log_file="${log_dir}"/deploy-workflow."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/deploy-workflow."${start_time}".log
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

    actions="|sign|encrypt|decrypt|"
    if [[ "${actions}" != *"|${action}|"* ]]
    then
        Login
        Compatiblity_Settings
    fi

    if [ -n "${object_path}" ]
    then
        comma=
        object_full_path=
        set -- "$(echo "${object_path}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            case "${i}" in
                */*)    object_full_path=${object_full_path}${comma}${i}
                        ;;
                *)      object_full_path=${object_full_path}${comma}$(Get_Path "$i")
                        ;;
            esac
            comma=,
        done
        object_path=${object_full_path}
    fi

    case "${action}" in
        export)             if [ -z "${folder}" ] || [ -n "${change}" ]
                            then
                                Export
                            else
                                Export_Folder
                            fi
                            ;;
        import)             Import
                            ;;
        import-deploy)      Import_Deploy
                            ;;
        deploy)             Deploy
                            ;;
        revoke)             Revoke
                            ;;
        release)            Release
                            ;;
        recall)             if [ -z "${folder}" ]
                            then
                                Recall
                            else
                                Recall_Folder
                            fi
                            ;;
        store)              Store
                            ;;
        revalidate)         Revalidate_Folder
                            ;;
        remove)             if [ -z "${folder}" ]
                            then
                                Remove
                            else
                                Remove_Folder
                            fi
                            ;;
        restore)            Restore
                            ;;
        delete)             if [ -z "${folder}" ]
                            then
                                Delete
                            else
                                Delete_Folder
                            fi
                            ;;
        sign)               if [ -n "${file}" ]
                            then
                                Sign_Workflow "${file}" "${hash}"
                            else
                                export key_file keystore_file key_password cert_file log_file show_logs verbose
                                export -f Log LogVerbose Sign_Workflow Cleanup
                                find "${directory}" -type f \( -name "*.workflow.json" -o -name "*.jobresource.json" \) -exec /bin/bash -c "set -e; trap 'Cleanup EXIT' EXIT; Sign_Workflow {} ${hash}" \;
                            fi
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

    actions="|sign|encrypt|decrypt|"
    if [[ "${actions}" != *"|${action}|"* ]]
    then
        Logout
    fi
}

# ------------------------------
# Cleanup trap
# ------------------------------

Cleanup()
{
    if [ -n "${temp_cert_file}" ] && [ -f "${temp_cert_file}" ]
    then
        rm -f "${temp_cert_file}"
    fi
    
    if [ -n "${sign_file}" ] && [ -f "${sign_file}".sig.bin ]
    then
        rm -f "${sign_file}".sig.bin
    fi

    if [ -n "${cert_file}" ] && [ -f "${cert_file}".pub ]
    then
        rm -f "${cert_file}".pub
    fi
}

End()
{
    Cleanup

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

    unset date_from
    unset folder
    unset start_folder
    unset object_path
    unset object_type
    unset new_object_path

    unset for_signing
    unset no_draft
    unset no_deployed
    unset no_released
    unset no_invalid
    unset use_short_path

    unset file
    unset format
    unset overwrite
    unset prefix
    unset suffix
    unset signature_algorithm
    unset change
    unset no_referencing
    unset no_references

    unset sign_file
    unset sign_dir
    unset keystore_file
    unset cert_file
    unset key_file
    unset key_password
    unset hash
    unset temp_cert_file
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
    unset changes_json
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
