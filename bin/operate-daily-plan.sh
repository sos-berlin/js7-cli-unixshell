#!/bin/bash

set -e

# ------------------------------------------------------------
# Company:  Software- und Organisations-Service GmbH
# Date:     2025-07-10
# Purpose:  Operate Daily Plan
# ------------------------------------------------------------
#
# Examples:
# ./operate-daily-plan.sh get-order --url=https://joc-2-0-primary.sos:7443 --user=root --password=root --controller-id=testsuite
#   --date-from=2025-07-11 --folder=/daily-plan/accounting,/daily-plan/invoicing --recursive
#     gets scheduled orders for the given date recursively from a list of workflow folders
#
# ./operate-daily-plan.sh cancel-order --url=https://joc-2-0-primary.sos:7443 --user=root --password=root --controller-id=testsuite
#   --date-to="$(TZ=Europe/London date --date="1 day ago" +'%Y-%m-%d')"
#     cancels scheduled orders of past days that did not coomplete using the Europe/London time zone
#
# ./operate-daily-plan.sh modify-order --url=https://joc-2-0-primary.sos:7443 --user=root -p --controller-id=testsuite
#   --date-from=2025-07-14 --date-to=2025-07-14 --scheduled-for=cur-02:00:00 --stick-to-plan
#     moves order start times 2 hours earlier for the given date 

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

item=
start_time=$(date +"%Y-%m-%dT%H-%M-%S")
response_json=
access_token=

schedule=
workflow=
schedule_folder=
workflow_folder=
order_id=
block_position=
start_position=
end_positions=
variable=
remove_variable=
date_from=
date_to=
scheduled_for=
time_zone=
state=
cycle=
recursive=false
force=false

overwrite=false
submit=false
non_auto_schedule=false
stick_to_plan=false
late=false
no_start_time=false
include_variables=false

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

Get_Timezone()
{
    if [ -z "${time_zone}" ]
    then
        if [ -n "${TZ}" ]
        then
            time_zone=${TZ}
        else
            if command -v timedatectl &> /dev/null
            then
                time_zone=$(timedatectl | grep -E -o  'Time zone: (.*)[ ]?.*\1' | cut -d' ' -f3)
                if [ ! "${time_zone}" = "$(timedatectl list-timezones | grep "${time_zone}")" ]
                then
                    time_zone=
                fi
            fi
        fi

        if [ -z "${time_zone}" ]
        then
            if [ -f /etc/timezone ]
            then
                time_zone=$(cat /etc/timezone)
            else
                if [ -f /etc/localtime ]
                then
                   full_info=$(readlink -f /etc/localtime)
                   zone_info="/usr/share/zoneinfo/"
                   time_zone=$(printf '%s' "${full_info//${zone_info}/}")
                fi
            fi
        fi

        if [ -z "${time_zone}" ]
        then
            LogError "could not determine system time zone, specify time zone using: --time-zone=<time-zone>"
            exit 1
        fi
    fi
}

Get_Order()
{
    LogVerbose ".. Get_Order()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateTo\": \"${date_to}\""
        request_comma=,
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}${request_comma} \"orderIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${state}" ]
    then
        request_body="${request_body}${request_comma} \"states\": ["
        request_comma=,
        comma=
        set -- "$(echo "${state}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ "${late}" = "true" ]
    then
        request_body="${request_body}${request_comma} \"late\": ${late}"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.plannedOrderItems[] // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Order() could not find object: ${response_json}"
                exit 3
            else
                if [ -z "${error_code}" ]
                then
                    # LogWarning "Get_Order() could not find orders: ${response_json}"
                    exit
                else
                    LogError "Get_Order() failed: ${response_json}"
                    exit 4
                fi
            fi
        else
            if [ "${include_variables}" = "true" ]
            then
                order_ids=$(echo "${response_json}" | jq -r '.plannedOrderItems[] | .orderId // empty')
                set -- "$(echo "${order_ids}" | sed -r 's/[,]+/ /g')"
                for i in $@; do
                    request_body="{ \"controllerId\": \"${controller_id}\", \"orderId\": \"${i}\" }"
                    LogVerbose ".... request:"
                    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/order/variables"
                    response_variables_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/order/variables)
                    LogVerbose ".... response:"
                    LogVerbose "${response_variables_json}"

                    if echo "${response_variables_json}" | jq -e . >/dev/null 2>&1
                    then
                        response_variables=$(echo "${response_variables_json}" | jq '.variables // empty')

                        if [ -z "${response_variables}" ]
                        then
                            error_code=$(echo "${response_variables_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')

                            if [ "${error_code}" = "JOC-400" ]
                            then
                                continue
                            else
                                if [ -z "${error_code}" ]
                                then
                                    # "Get_Order() could not find orders: ${response_variables_json}"
                                    continue
                                else
                                    LogError "Get_Order() failed: ${response_variables_json}"
                                    exit 4
                                fi
                            fi
                        else
                            response_json=$(echo "${response_json}" | jq "(.plannedOrderItems[] | select(.orderId == \"${i}\")) |= .+ { variables: $(echo ${response_variables}) }")
                        fi
                    fi
                done
            fi

            echo "${response_json}" | jq '.plannedOrderItems // empty'
        fi
    else
        LogError "Get_Order() failed: ${response_json}"
        exit 4
    fi
}

Cancel_Order()
{
    LogVerbose ".. Cancel_Order()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateTo\": \"${date_to}\""
        request_comma=,
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}${request_comma} \"orderIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders/cancel"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/cancel)
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
                LogWarning "Cancel_Order() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Cancel_Order() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Cancel_Order() failed: ${response_json}"
        exit 4
    fi
}

Copy_Order()
{
    LogVerbose ".. Copy_Order()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}, \"orderIds\": ["
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${scheduled_for}" ]
    then
        request_body="${request_body}, \"scheduledFor\": \"${scheduled_for}\""
    fi

    if [ -n "${time_zone}" ]
    then
        request_body="${request_body}, \"timeZone\": \"${time_zone}\""
    fi

    if [ -n "${cycle}" ]
    then
        request_body="${request_body}, \"cycle\": \"${cycle}\""
    fi

    request_body="${request_body}, \"forceJobAdmission\": ${force}"
    request_body="${request_body}, \"stickDailyPlanDate\": ${stick_to_plan}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_paln/orders/copy"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/copy)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.orderIds[] // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Copy_Order() could not find object: ${response_json}"
                exit 3
            else
                LogError "Copy_Order() failed: ${response_json}"
                exit 4
            fi
        else
           echo "${response_json}" | jq -r '.orderIds // empty'
        fi
    else
        LogError "Copy_Order() failed: ${response_json}"
        exit 4
    fi
}

Generate_Order()
{
    LogVerbose ".. Generate_Order()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}, \"dailyPlanDate\": \"${date_from}\""
    fi

    if [ -n "${schedule}" ] || [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}, \"schedulePaths\": {"
        request_comma=
        
        if [ -n "${schedule}" ]
        then
            request_body="${request_body} \"singles\": ["
            request_comma=,
            comma=
            set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} \"${i}\""
                comma=,
            done
            request_body="${request_body} ]"
        fi
    
        if [ -n "${schedule_folder}" ]
        then
            request_body="${request_body}${request_comma} \"folders\": ["
            comma=
            set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
                comma=,
            done
            request_body="${request_body} ]"
        fi

        request_body="${request_body} }"
    fi

    if [ -n "${workflow}" ] || [ -n "${workflow_folder}" ]
    then  
        request_body="${request_body}, \"workflowPaths\": {"
        request_comma=

        if [ -n "${workflow}" ]
        then
            request_body="${request_body}${request_comma} \"singles\": ["
            request_comma=,
            comma=
            set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} \"${i}\""
                comma=,
            done
            request_body="${request_body} ]"
        fi
    
        if [ -n "${workflow_folder}" ]
        then
            request_body="${request_body}${request_comma} \"folders\": ["
            comma=
            set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
            for i in $@; do
                request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
                comma=,
            done
            request_body="${request_body} ]"
        fi

        request_body="${request_body} }"
    fi

    request_body="${request_body}, \"overwrite\": ${overwrite}"
    request_body="${request_body}, \"withSubmit\": ${submit}"
    request_body="${request_body}, \"includeNonAutoPlannedOrders\": ${non_auto_schedule}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders/generate"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/generate)
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
                LogWarning "Generate_Order() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Generate_Order() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Generate_Order() failed: ${response_json}"
        exit 4
    fi
}

Submit_Order()
{
    LogVerbose ".. Submit_Order()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateFrom\": \"${date_from}\""
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateTo\": \"${date_to}\""
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}${request_comma} \"orderIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders/submit"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/submit)
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
                LogWarning "Submit_Order() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Submit_Order() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Submit_Order() failed: ${response_json}"
        exit 4
    fi
}

Delete_Order()
{
    LogVerbose ".. Delete_Order()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dailyPlanDateTo\": \"${date_to}\""
        request_comma=,
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}${request_comma} \"orderIds\": ["
        request_comma=,
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"late\": $late"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/delete)
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
                LogWarning "Delete_Order() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Order() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Order() failed: ${response_json}"
        exit 4
    fi
}

Modify_Order()
{
    LogVerbose ".. Modify_Order()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""

    if [ -n "${scheduled_for}" ]
    then
        request_body="${request_body}, \"scheduledFor\": \"${scheduled_for}\""
    fi

    if [ -n "${time_zone}" ]
    then
        request_body="${request_body}, \"timeZone\": \"${time_zone}\""
    fi

    if [ -n "${order_id}" ]
    then
        request_body="${request_body}, \"orderIds\": ["
        comma=
        set -- "$(echo "${order_id}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${cycle}" ]
    then
        request_body="${request_body}, \"cycle\": \"${cycle}\""
    fi

    if [ -n "${variable}" ]
    then
        request_body="${request_body}, \"variables\": {"
        comma=
        set -- "$(echo "${variable}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            IFS='=' read -ra var <<< "$i"
            request_body="${request_body}${comma} \"${var[0]}\": \"${var[1]}\""
            comma=,
        done
        request_body="${request_body} }"
    fi

    if [ -n "${remove_variable}" ]
    then
        request_body="${request_body}, \"removeVariables\": ["
        comma=
        set -- "$(echo "${remove_variable}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${block_position}" ]
    then
        request_body="${request_body}, \"blockPosition\": \"${block_position}\""
    fi

    if [ -n "${start_position}" ]
    then
        request_body="${request_body}, \"startPosition\": \"${start_position}\""
    fi

    if [ -n "${end_positions}" ]
    then
        request_body="${request_body}${request_comma} \"endPositions\": ["
        comma=
        set -- "$(echo "${end_positions}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"forceJobAdmission\": ${force}"
    request_body="${request_body}, \"stickDailyPlanDate\": ${stick_to_plan}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/orders/modify"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/orders/modify)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.orderIds // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Modify_Order() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Modify_Order() failed: ${response_json}"
                exit 4
            fi
        else
           echo "${response_json}" | jq -r '.orderIds // empty'
        fi
    else
        LogError "Modify_Order() failed: ${response_json}"
        exit 4
    fi
}

Delete_Submission()
{
    LogVerbose ".. Delete_Submission()"
    Curl_Options

    request_body="{ \"controllerId\": \"${controller_id}\""
    request_body="${request_body}, \"filter\": {"

    if [ -n "${date_to}" ] && [ ! "${date_to}" = "${date_from}" ]
    then
        request_body="${request_body} \"dateFrom\": \"${date_from}\""
        request_body="${request_body}, \"dateTo\": \"${date_to}\""
    else
        request_body="${request_body} \"dateFor\": \"${date_from}\""
    fi

    request_body="${request_body} }"

    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/submissions/delete"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/submissions/delete)
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
                LogWarning "Delete_Submission() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Delete_Submission() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Delete_Submission() failed: ${response_json}"
        exit 4
    fi
}

Create_Projection()
{
    LogVerbose ".. Create_Projection()"
    Curl_Options

    request_body="{"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/projections/recreate"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/projections/recreate)
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
                LogWarning "Create_Projection() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Create_Projection() failed: ${response_json}"
                exit 4
            fi
        fi
    else
        LogError "Create_Projection() failed: ${response_json}"
        exit 4
    fi
}

Get_Projection_Calendar()
{
    LogVerbose ".. Get_Projection_Calendar()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dateTo\": \"${date_to}\""
        request_comma=,
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"withoutStartTime\": ${no_start_time}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/projections/calendar"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/projections/calendar)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.years // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Projection_Calendar() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Projection_Calendar() failed: ${response_json}"
                exit 4
            fi
        else
            echo "${response_json}" | jq '.years[] // empty'
        fi
    else
        LogError "Get_Projection_Calendar() failed: ${response_json}"
        exit 4
    fi
}

Get_Projection_Date()
{
    LogVerbose ".. Get_Projection_Date()"
    Curl_Options

    request_body="{ "
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

    if [ -n "${date_from}" ]
    then
        request_body="${request_body}${request_comma} \"dateFrom\": \"${date_from}\""
        request_comma=,
    fi

    if [ -n "${date_to}" ]
    then
        request_body="${request_body}${request_comma} \"dateTo\": \"${date_to}\""
        request_comma=,
    fi

    if [ -n "${schedule}" ]
    then
        request_body="${request_body}${request_comma} \"schedulePaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${schedule_folder}" ]
    then
        request_body="${request_body}${request_comma} \"scheduleFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${schedule_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow}" ]
    then
        request_body="${request_body}${request_comma} \"workflowPaths\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} \"${i}\""
            comma=,
        done
        request_body="${request_body} ]"
    fi

    if [ -n "${workflow_folder}" ]
    then
        request_body="${request_body}${request_comma} \"workflowFolders\": ["
        request_comma=,
        comma=
        set -- "$(echo "${workflow_folder}" | sed -r 's/[,]+/ /g')"
        for i in $@; do
            request_body="${request_body}${comma} {\"folder\": \"${i}\", \"recursive\": ${recursive}}"
            comma=,
        done
        request_body="${request_body} ]"
    fi

    request_body="${request_body}, \"withoutStartTime\": ${no_start_time}"
    Audit_Log_Request
    request_body="${request_body} }"

    LogVerbose ".... request:"
    LogVerbose "curl ${curl_log_options[*]} -H \"X-Access-Token: ${access_token}\" -H \"Accept: application/json\" -H \"Content-Type: application/json\" -d ${request_body} ${joc_url}/joc/api/daily_plan/projections/dates"
    response_json=$(curl "${curl_options[@]}" -H "X-Access-Token: ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -d "${request_body}" "${joc_url}"/joc/api/daily_plan/projections/dates)
    LogVerbose ".... response:"
    LogVerbose "${response_json}"

    if echo "${response_json}" | jq -e . >/dev/null 2>&1
    then
        ok=$(echo "${response_json}" | jq -r '.years // empty' | sed 's/^"//' | sed 's/"$//')
        if [ -z "${ok}" ]
        then
            error_code=$(echo "${response_json}" | jq -r '.error.code // empty' | sed 's/^"//' | sed 's/"$//')
            if [ "${error_code}" = "JOC-400" ]
            then
                LogWarning "Get_Projection_Date() could not find objects: ${response_json}"
                exit 3
            else
                LogError "Get_Projection_Date() failed: ${response_json}"
                exit 4
            fi
         else
            echo "${response_json}" | jq '.years[] // empty'
        fi
    else
        LogError "Get_Projection_Date() failed: ${response_json}"
        exit 4
    fi
}

Usage()
{
    >&"$1" echo ""
    >&"$1" echo "Usage: $(basename "$0") [Command] [Options] [Switches]"
    >&"$1" echo ""
    >&"$1" echo "  Commands:"
    >&"$1" echo "    get-order        [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--late] [--state] [-a]"
    >&"$1" echo "    submit-order     [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive]"
    >&"$1" echo "    cancel-order     [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--late] [--state]"
    >&"$1" echo "    delete-order     [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--late]"
    >&"$1" echo "    generate-order    --date-from  [--submit] [--overwrite] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--non-auto-plan]"
    >&"$1" echo "    copy-order       [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--stick-to-plan]"
    >&"$1" echo "                      --scheduled-for [--time-zone] [--cycle] [--force]"
    >&"$1" echo "    modify-order     [--date-from] [--date-to] [--order-id] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--stick-to-plan]"
    >&"$1" echo "                     [--scheduled-for] [--time-zone] [--cycle] [--variable] [--remove-variable]"
    >&"$1" echo "                     [--start-position] [--block-position] [--end-position] [--force]"
    >&"$1" echo "    delete-submission --date-from  [--date-to]"
    >&"$1" echo "    get-pro-calendar  --date-from  [--date-to] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--no-start-time]"
    >&"$1" echo "    get-pro-date      --date-from  [--date-to] [--schedule] [--workflow] [--schedule-folder] [--workflow-folder] [--recursive] [--no-start-time]"
    >&"$1" echo "    create-pro"
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
    >&"$1" echo "    --block-position=<label>           | optional: label for block instruction that holds start position"
    >&"$1" echo "    --start-position=<label>           | optional: label from which the order will be started"
    >&"$1" echo "    --end-position=<label[,label]>     | optional: list of labels before which the order will terminate"
    >&"$1" echo "    --variable=<key=value[,key=value]> | optional: list of variables holding key/value pairs"
    >&"$1" echo "    --date-from=<date>                 | optional: daily plan begin of date range"
    >&"$1" echo "    --date-to=<date>                   | optional: daily plan end of date range"
    >&"$1" echo "    --scheduled-for=<date|time|offset> | optional: order start date for copy-order, start time for modify-order"
    >&"$1" echo "    --time-zone=<tz>                   | optional: time zone for dates, default: ${time_zone}"
    >&"$1" echo "                                                   see https://en.wikipedia.org/wiki/List_of_tz_database_time_zones"
    >&"$1" echo "    --state=<state[,state]>            | optional: list of states limiting orders to be processed such as"
    >&"$1" echo "                                                   PLANNED, SUBMITTED, FINISHED"
    >&"$1" echo "    --schedule=<name[,name]>           | optional: list of schedule names"
    >&"$1" echo "    --schedule-folder=<path[,path]>    | optional: list of folders holding schedules"
    >&"$1" echo "    --workflow=<name[,name]>           | optional: list of workflow names"
    >&"$1" echo "    --workflow-folder=<path[,path]>    | optional: list of folders holding workflows"
    >&"$1" echo "    --order-id=<id[,id]>               | optional: list of order identifiers"
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
    >&"$1" echo "    -r | --recursive                   | specifies folders to be looked up recursively"
    >&"$1" echo "    -a | --order-variables             | specifies variables to be included with results to get-order command"
    >&"$1" echo "    -s | --submit                      | submits orders when used with the generate-order command"
    >&"$1" echo "    -l | --late                        | includes late orders with get/cancel operations"
    >&"$1" echo "    -i | --stick-to-plan               | specifies to stick to the daily plan assignment"
    >&"$1" echo "    -n | --non-auto-plan               | includes schedules without automated planning"
    >&"$1" echo "    -t | --no-start-time               | inverts projections to return dates without start times"
    >&"$1" echo "    -f | --force                       | specifies forced start of jobs ignoring admission times"
    >&"$1" echo "    --show-logs                        | shows log output if --log-dir is used"
    >&"$1" echo "    --make-dirs                        | creates directories if they do not exist"
    >&"$1" echo ""
    >&"$1" echo "see https://kb.sos-berlin.com/x/sQUeCw"
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

    Get_Timezone

    case "$1" in
        get-order|cancel-order|submit-order|delete-order|generate-order|modify-order|copy-order|delete-submission|get-pro-calendar|get-pro-date|create-pro) action=$1
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
            --block-position=*)     block_position=$(echo "${option}" | sed 's/--block-position=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --start-position=*)     start_position=$(echo "${option}" | sed 's/--start-position=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --end-position=*)       end_positions=$(echo "${option}" | sed 's/--end-position=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --variable=*)           variable=$(echo "${option}" | sed 's/--variable=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --remove-variable=*)    remove_variable=$(echo "${option}" | sed 's/--remove-variable=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --date-from=*)          date_from=$(echo "${option}" | sed 's/--date-from=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --date-to=*)            date_to=$(echo "${option}" | sed 's/--date-to=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --scheduled-for=*)      scheduled_for=$(echo "${option}" | sed 's/--scheduled-for=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --time-zone=*)          time_zone=$(echo "${option}" | sed 's/--time-zone=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --order-id=*)           order_id=$(echo "${option}" | sed 's/--order-id=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --state=*)              state=$(echo "${option}" | sed 's/--state=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --schedule=*)           schedule=$(echo "${option}" | sed 's/--schedule=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --schedule-folder=*)    schedule_folder=$(echo "${option}" | sed 's/--schedule-folder=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --workflow=*)           workflow=$(echo "${option}" | sed 's/--workflow=//' | sed 's/^"//' | sed 's/"$//' | sed 's/^\(.*\)\/$/\1/')
                                    ;;
            --workflow-folder=*)    workflow_folder=$(echo "${option}" | sed 's/--workflow-folder=//' | sed 's/^"//' | sed 's/"$//')
                                    ;;
            --order-id=*)           order_id=$(echo "${option}" | sed 's/--order-id=//' | sed 's/^"//' | sed 's/"$//')
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
            -r|--recursive)         recursive=true
                                    ;;
            -a|--order-variables)   include_variables=true
                                    ;;
            -s|--submit)            submit=true
                                    ;;
            -l|--late)              late=true
                                    ;;
            -i|--stick-to-plan)     stick_to_plan=true
                                    ;;
            -n|--non-auto-plan)     non_auto_schedule=true
                                    ;;
            -t|--no-start-time)     no_start_time=true
                                    ;;
            -f|--force)             force=true
                                    ;;
            --make-dirs)            make_dirs=1
                                    ;;
            --show-logs)            show_logs=1
                                    ;;
            get-order|cancel-order|submit-order|delete-order|generate-order|modify-order|copy-order|delete-submission|get-pro-calendar|get-pro-date|create-pro)
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

    actions="|generate-order|delete-submission|get-pro-calendar|get-pro-date|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${date_from}" ]
    then
        Usage 2
        LogError "Command ${action} requires to specify the start date: --date-from"
        exit 1
    fi

    actions="|get-order|cancel-order|submit-order|delete-order|copy-order|modify-order|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${date_from}" ] && [ -z "${order_id}" ]
    then
        date_from=$(TZ="${time_zone}" date +'%Y-%m-%d')
    fi

    actions="|copy-order|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${scheduled_for}" ]
    then
        Usage 2
        LogError "Command ${action} requires to specify the date for which orders will be scheduled --scheduled-for"
        exit 1
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

    actions="|get-order|cancel-order|submit-order|delete-order|copy-order|modify-order|delete-submission|get-pro-calendar|get-pro-date|"
    if [[ "${actions}" == *"|${action}|"* ]] && [ -z "${date_to}" ]
    then
        date_to="${date_from}"
    fi

    # initialize logging
    if [ -n "${log_dir}" ]
    then
        # create log directory if required
        if [ ! -d "${log_dir}" ] && [ -n "${make_dirs}" ]
        then
            mkdir -p "${log_dir}"
        fi
    
        log_file="${log_dir}"/operate-daily-plan."${start_time}".log
        while [ -f "${log_file}" ]
        do
            sleep 1
            start_time=$(date +"%Y-%m-%dT%H-%M-%S")
            log_file="${log_dir}"/operate-daily-plan."${start_time}".log
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
        get-order)          Get_Order
                            ;;
        cancel-order)       if [ -z "${state}" ]
                            then
                                state=SUBMITTED
                            fi

                            if [ -z "${order_id}" ]
                            then
                                order_id=$(Get_Order | jq -r '.[].orderId // empty')
                            fi

                            if [ -n "${order_id}" ]
                            then
                                Cancel_Order
                            else
                                LogWarning "Cancel_Order() could not find orders."
                                exit 3
                            fi
                            ;;
        submit-order)       state=PLANNED
                            if [ -z "${order_id}" ]
                            then
                                order_id=$(Get_Order | jq -r '.[].orderId // empty')
                            fi

                            if [ -n "${order_id}" ]
                            then
                                Submit_Order
                            else
                                LogWarning "Submit_Order() could not find orders."
                                exit 3
                            fi
                            ;;
        delete-order)       state=PLANNED
                            if [ -z "${order_id}" ]
                            then
                                order_id=$(Get_Order | jq -r '.[].orderId // empty')
                            fi

                            if [ -n "${order_id}" ]
                            then
                                Delete_Order
                            else
                                LogWarning "Delete_Order() could not find orders"
                                exit 3
                            fi
                            ;;
        generate-order)     Generate_Order
                            ;;
        modify-order)       if [ -z "${state}" ]
                            then
                                state=SUBMITTED,PLANNED
                            fi

                            if [ -z "${order_id}" ]
                            then
                                order_id=$(Get_Order | jq -r '.[].orderId // empty')
                            fi

                            if [ -n "${order_id}" ]
                            then
                                Modify_Order
                            else
                                LogWarning "Modify_Order() could not find orders"
                                exit 3
                            fi
                            ;;
        copy-order)         if [ -z "${order_id}" ]
                            then
                                order_id=$(Get_Order | jq -r '.[].orderId // empty')
                            fi

                            if [ -n "${order_id}" ]
                            then
                                Copy_Order
                            else
                                LogWarning "Copy_Order() could not find orders"
                                exit 3
                            fi
                            ;;
        delete-submission)  Delete_Submission
                            ;;
        get-pro-calendar)   Get_Projection_Calendar
                            ;;
        get-pro-date)       Get_Projection_Date
                            ;;
        create-pro)         Create_Projection
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

    unset schedule
    unset workflow
    unset schedule_folder
    unset workflow_folder
    unset order_id
    unset block_position
    unset start_position
    unset end_positions
    unset variable
    unset remove_variable
    unset date_from
    unset date_to
    unset scheduled_for
    unset time_zone
    unset full_info
    unset zone_info
    unset state
    unset cycle
    unset recursive
    unset force
    unset overwrite
    unset submit
    unset non_auto_schedule
    unset stick_to_plan
    unset late
    unset no_start_time
    unset include_variables

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
