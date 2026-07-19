#!/bin/bash

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password=root --ca-cert=./root-ca.crt)

# use client authentication ceertificate
request_options=(--url=https://joc-2-0-primary.sos:7443 --ca-cert=./root-ca.crt --client-cert=./agent-2-0-primary.rsa.crt --client-key=./agent-2-0-primary.rsa.key)

# ------------------------------ Status ----------

# get status information on JOC Cockpit and Controller instances
./operate-joc.sh status "${request_options[@]}" --controller-id=testsuite

# get status informaiton on Agents
./operate-joc.sh status-agent "${request_options[@]}" --controller-id=testsuite

# get status informiaton on Agents limited by state
./operate-joc.sh status-agent "${request_options[@]}" --controller-id=testsuite --agent-id=agent_001,agent_002

# ------------------------------ Health Check ----------

# perform health check
./operate-joc.sh health-check "${request_options[@]}" --controller-id=testsuite

# perform health check for host shutdown scenario
./operate-joc.sh health-check "${request_options[@]}" --controller-id=testsuite --agent-cluster --whatif-shutdown=joc-2-0-primary

# ------------------------------ Switch-over ----------

# switch-over active role
./operate-joc.sh switch-over "${request_options[@]}" --controller-id=testsuite

# ------------------------------ Restart / Run Service ----------

# restart service: cluster, history, dailyplan, cleanup, monitor
./operate-joc.sh restart-service "${request_options[@]}" --service-type=dailyplan

# run service: dailyplan, cleanup
./operate-joc.sh run-service "${request_options[@]}" --service-type=dailyplan

# restart proxies
./operate-joc.sh restart-service "${request_options[@]}" --proxies

# ------------------------------ Settings ----------

# get settings
settings=$(./operate-joc.sh get-settings "${request_options[@]}")

# update settings
settings=$(echo "${settings}" | jq '.dailyplan.projections_month_ahead.value = "19"')

# store settings
./operate-joc.sh store-settings "${request_options[@]}" --settings="${settings}"

# ------------------------------ Report ----------

# report daily plan by start date
./operate-joc.sh report-daily-plan "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-09"

# report daily plan  by workflow for date range
./operate-joc.sh report-daily-plan "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-08" --workflow=pdwScheduledWorkflow_003 --csv > ./out.csv

# report daily plan by workflow folder recursively for date range
./operate-joc.sh report-daily-plan "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-08" --folder=/ProductDemo --recursive --csv > ./out.csv

# report daily plan by schedule for date range
./operate-joc.sh report-daily-plan "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-08" --schedule=pdsScheduledWorkflowDaily --csv > ./out.csv

# report daily plan by tags for date range
./operate-joc.sh report-daily-plan "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-08" --tag=ScheduledExecution,ProductDemo --csv > ./out.csv


# report order history for date range with limit
./operate-joc.sh report-order-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" --limit=20 --csv > ./out.csv

# report order history by workflow for date range
./operate-joc.sh report-order-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" --workflow=pdwScheduledWorkflow_003 --csv > ./out.csv

# report order history by workflow folder recursively for date range
./operate-joc.sh report-order-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08T00:00:00" --date-to="2024-12-08T23:59:59" \
                                                           --time-zone="Etc/UTC" --folder=/ProductDemo --recursive --csv > ./out.csv
# report order history by tags for date range
./operate-joc.sh report-order-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08T00:00:00" --date-to="2024-12-08T23:59:59" \
                                                           --time-zone="Etc/UTC" --tag=ProductDemo --csv > ./out.csv
# report  order history by state for date range
./operate-joc.sh report-order-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08T00:00:00" --date-to="2024-12-08T23:59:59" \
                                                           --time-zone="Etc/UTC" --state=failed  --csv > ./out.csv

# report task history for date range with limit
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --limit=20 --csv > ./out.csv
# report task history by workflow for date range
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --workflow=pdwScheduledWorkflow_003 --csv > ./out.csv
# report task history by workflow and job for date range
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --workflow=pdwScheduledWorkflow_003 --job=job2_2b --csv > ./out.csv
# report task history by job for date range
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --job=job2_2b --csv > ./out.csv
# report task history by criticality
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --criticalities=critical,major --csv > ./out.csv
# report task history by workflow tags and date range
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \
                                                          --tag=ProductDemo,ScheduledExecution --csv > ./out.csv
# report task history by order tags and date range
./operate-joc.sh report-task-history "${request_options[@]}" --controller-id=testsuite --date-from="2024-12-08" --date-to="2024-12-09" \


# report file transfer history for date range
./operate-joc.sh report-transfer-history "${request_options[@]}" --controller-id=testsuite --date-from="2026-05-01" --date-to="2026-06-15" \
                                                                 --csv > ./out.csv

# report file transfer history for successful transfers by the given workflow in the date range of two days ago until begin of current day
./operate-joc.sh report-transfer-history "${request_options[@]}" --controller-id=testsuite --date-from="2026-05-01" --date-to="2026-06-15" \
                                                                 --state=SUCCESSFUL,FAILED \
                                                                 --workflow=pdwWatchFileAndTransferFile \
                                                                 --csv > ./out.csv


# report file transfer for files
./operate-joc.sh report-transfer-file    "${request_options[@]}" --controller-id=testsuite --date-from="2026-05-01" --date-to="2026-06-15" \
                                                          --state=SUCCESSFUL,FAILED --profile=ab,product_demo_to_demo_file_path_sftp \
                                                          --csv > out.csv

# ------------------------------ License ----------

# check license
./operate-joc.sh check-license "${request_options[@]}"

# ------------------------------ Version ----------

# get version
./operate-joc.sh version "${request_options[@]}"
./operate-joc.sh version "${request_options[@]}" --controller-id=testsuite
./operate-joc.sh version "${request_options[@]}" --agent-id=StandaloneAgentHttpId
./operate-joc.sh version "${request_options[@]}" --agent-id=MyAgentClusterId_01
./operate-joc.sh version "${request_options[@]}" --controller-id=standalone --agent-id=agent_003

# ------------------------------ Encrypted Passwords ----------

# create Private Key
openssl ecparam -name secp384r1 -genkey -noout -out ./ca/private/encrypt.key

# create Certificate Signing Request
openssl req -new -sha512 -nodes -key ./ca/private/encrypt.key -out ./ca/csr/encrypt.csr -subj "/C=DE/ST=Berlin/L=Berlin/O=SOS/OU=IT/CN=Encrypt"

# create Certificate
openssl x509 -req -sha512 -days 1825 -signkey ./ca/private/encrypt.key -in ./ca/csr/encrypt.csr -out ./ca/certs/encrypt.crt -extfile <(printf "keyUsage=critical,keyEncipherment,keyAgreement\n")

# encrypt
result=$(./operate-joc.sh encrypt --in=root --cert=./ca/certs/encrypt.crt --java-home=/opt/java/jdk-21)

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password="${result}" --key=./ca/private/encrypt.key --java-home=/opt/java/jdk-21 --controller-id=testsuite --ca-cert=./root-ca.crt)

# check license
./operate-joc.sh check-license "${request_options[@]}"
