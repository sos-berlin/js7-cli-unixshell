#!/bin/bash

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password=root --controller-id=testsuite --ca-cert=./root-ca.crt)

# ------------------------------ Orders ----------

# get orders for current daily plan date
./operate-daily-plan.sh get-order "${request_options[@]}"

# get late orders for current daily plan date
./operate-daily-plan.sh get-order "${request_options[@]}" --late

# get orders for daily plan date
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11

# get orders for daily plan date range
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11 --date-to=2025-07-17

# get orders for current date in the given time zone
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=$(TZ=Europe/London date +'%Y-%m-%d')

# get orders for last 5 days in the given time zone
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=$(TZ=Europe/London date --date="6 day ago" +'%Y-%m-%d') --date-to=$(TZ=Europe/London date --date="1 day ago" +'%Y-%m-%d')

# get orders for daily plan date and process results
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-14 | jq -r '.[] | .orderId'

# get orders for daily plan date and schedules
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11 --schedule=pdsScheduledWorkflowCyclic,pdTaggingOrders-01

# get orders for daily plan date and schedule folders
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11 --schedule-folder=/ProductDemo --recursive

# get orders for daily plan date and workflows
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11 --workflow=pdwScheduledWorkflow_001,pdwScheduledWorkflow_002

# get orders for daily plan date and workflow folders
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-11 --workflow-folder=/ProductDemo --recursive

# get orders for daily plan date and status
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-10 --state=SUBMITTED

# get orders for daily plan date and late execution
./operate-daily-plan.sh get-order "${request_options[@]}" --date-from=2025-07-10 --late


# submit orders for daily plan date
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-13

# submit orders for daily plan date range
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-10 --date-to=2025-07-10

# submit orders for daily plan date and schedules
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-11 --schedule=pdsScheduledWorkflowCyclic,pdTaggingOrders-01

# submit orders for daily plan date and schedule folders
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-11 --schedule-folder=/ProductDemo --recursive

# submit orders for daily plan date and workflows
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-11 --workflow=pdwScheduledWorkflow_001,pdwScheduledWorkflow_002

# submit orders for daily plan date and workflow folders
./operate-daily-plan.sh submit-order "${request_options[@]}" --date-from=2025-07-11 --workflow-folder=/ProductDemo --recursive


# cancel orders for daily plan date
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-13

# cancel orders for daily plan date range
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-10 --date-to=2025-07-14

# cancel orders for daily plan date and schedules
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-11 --schedule=pdsScheduledWorkflowCyclic,pdTaggingOrders-01

# cancel orders for daily plan date and schedule folders
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-11 --schedule-folder=/ProductDemo --recursive

# cancel orders for daily plan date and workflows
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-11 --workflow=pdwScheduledWorkflow_001,pdwScheduledWorkflow_002

# cancel orders for daily plan date and workflow folders
./operate-daily-plan.sh cancel-order "${request_options[@]}" --date-from=2025-07-11 --workflow-folder=/ProductDemo --recursive


# delete orders for daily plan date
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-13

# delete orders for daily plan date range
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-10 --date-to=2025-07-10

# delete orders for daily plan date and schedules
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-14 --schedule=pdsScheduledWorkflowCyclic,pdTaggingOrders-01

# delete orders for daily plan date and schedule folders
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-14 --schedule-folder=/ProductDemo --recursive

# delete orders for daily plan date and workflows
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-14 --workflow=pdwScheduledWorkflow_001,pdwScheduledWorkflow_002

# delete orders for daily plan date and workflow folders
./operate-daily-plan.sh delete-order "${request_options[@]}" --date-from=2025-07-14 --workflow-folder=/ProductDemo --recursive


# generate orders starting for daily plan date
./operate-daily-plan.sh generate-order "${request_options[@]}" --date-from=2025-07-14

# generate orders for daily plan date and schedules
./operate-daily-plan.sh generate-order "${request_options[@]}" --date-from=2025-07-14 --schedule=pdsScheduledWorkflowCyclic,pdTaggingOrders-01

# generate orders for daily plan date and schedule folders
./operate-daily-plan.sh generate-order "${request_options[@]}" --date-from=2025-07-14 --schedule-folder=/ProductDemo --recursive

# generate orders for daily plan date and workflows
./operate-daily-plan.sh generate-order "${request_options[@]}" --date-from=2025-07-14 --workflow=pdwScheduledWorkflow_001,pdwScheduledWorkflow_002

# generate orders for daily plan date and workflow folders
./operate-daily-plan.sh generate-order "${request_options[@]}" --date-from=2025-07-14 --workflow-folder=/ProductDemo --recursive


# move order start times 2 hours earlier for daily plan date and keep daily plan assignment
./operate-daily-plan.sh modify-order "${request_options[@]}" --date-from=2025-07-14 --scheduled-for=cur-02:00:00 --stick-to-plan

# move order start times 2 hours later for daily plan date and keep daily plan assignment
./operate-daily-plan.sh modify-order "${request_options[@]}" --date-from=2025-07-14 --scheduled-for=cur+02:00:00 --stick-to-plan

# modify order start times for immediate execution of a number of workflows
./operate-daily-plan.sh modify-order "${request_options[@]}" --date-from=2025-07-14 --scheduled-for=now --stick-to-plan --workflow-folder=/ProductDemo --recursive

# modify order variables
./operate-daily-plan.sh modify-order "${request_options[@]}" --order-id="#2025-07-14#P26757473449-daily-2,#2025-07-14#P26757473247-daily-1" --variable="booking_code=9999,booking_number=39"

# remove order variables
./operate-daily-plan.sh modify-order "${request_options[@]}" --order-id="#2025-07-14#P32659837830-daily-2,#2025-07-14#P32659837729-daily-1" --remove-variable="booking_number,booking_code"
                                        

# copy orders from given date to target date
./operate-daily-plan.sh copy-order "${request_options[@]}" --date-from=2025-07-14 --scheduled-for=2025-07-28

# copy orders from given date range to target date
./operate-daily-plan.sh copy-order "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17 --scheduled-for=2025-07-28

# copy order from given date and workflow folder to target date
./operate-daily-plan.sh copy-order "${request_options[@]}" --date-from=2025-07-14 --scheduled-for=2025-07-28 --workflow-folder=/ProductDemo --recursive


# delete submission for given daily plan date
./operate-daily-plan.sh delete-submission "${request_options[@]}" --date-from=2025-07-14

# cleanup daily plan for the given date range
./operate-daily-plan.sh cancel-order      "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17
./operate-daily-plan.sh delete-order      "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17
./operate-daily-plan.sh delete-submission "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17


# get projected calendar dates of order starts in date range
./operate-daily-plan.sh get-pro-calendar "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17

# get projected calendar dates of order starts in date range filtered by schedules
./operate-daily-plan.sh get-pro-calendar "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17 --schedule-folder=/ProductDemo --recursive

# get projected calendar dates without order starts in date range filtered by schedule folders
./operate-daily-plan.sh get-pro-calendar "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17 --schedule-folder=/ProductDemo --recursive --no-start-time

# get projected dates/times of order starts for date range
./operate-daily-plan.sh get-pro-date "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17

# get projected dates/times of order starts in date range filtered by schedules
./operate-daily-plan.sh get-pro-date "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17 --schedule-folder=/ProductDemo --recursive

# get projected dates/times without order starts in date range filtered by schedules
./operate-daily-plan.sh get-pro-date "${request_options[@]}" --date-from=2025-07-14 --date-to=2025-07-17 --schedule-folder=/ProductDemo --recursive --no-start-time

# create projections
./operate-daily-plan.sh create-pro "${request_options[@]}"
