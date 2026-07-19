#!/bin/bash

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password=root --controller-id=testsuite --ca-cert=./root-ca.crt)

# ------------------------------ Orders ----------

# add ad hoc order
./operate-workflow.sh add-order "${request_options[@]}" --workflow=ap3jobs

# add ad hoc order
./operate-workflow.sh add-order "${request_options[@]}" --date-to=now --workflow=ap3jobs --order-name=sample-1 --start-position=job2 --end-position=job3

# add timed order for the next day in specific time zone
./operate-workflow.sh add-order "${request_options[@]}" \
    --workflow=ap3Jobs --date-to="$(TZ=Asia/Tokyo date --date='+1 day' +'%Y-%m-%d %H:%M:%S')" --time-zone=Asia/Tokyo

# add timed order for a point in time in 3 minutes, time zone must be Etc/UTC
./operate-workflow.sh add-order "${request_options[@]}" \
    --workflow=ap3Jobs --date-to="now+180" --time-zone=Etc/UTC

# add pending order
./operate-workflow.sh add-order "${request_options[@]}" --date-to=never --workflow=ap3jobs --order-name=sample-1 --start-position=job2 --end-position=job3

# add scheduled order and force admission
./operate-workflow.sh add-order "${request_options[@]}" --date-to=now+15 --workflow=ap3jobs --order-name=sample-1 --start-position=job2 --end-position=job3 --force

# add ad hoc order with variables
./operate-workflow.sh add-order "${request_options[@]}" --date-to=now --workflow=ap3jobs --variable="var1=new string,var2=24,var3=true"


# add ad hoc order and feed audit log
./operate-workflow.sh add-order "${request_options[@]}" --workflow=ap3jobs \
    --audit-message="order added by operate-workflow.sh" --audit-time-spent=1 \
    --audit-link="https://www.sos-berlin.com"


# get order by ID
./operate-workflow.sh get-order "${request_options[@]}" --order-id="#2025-04-09#T22240566772-root"

# get orders by workflows
./operate-workflow.sh get-order "${request_options[@]}" --workflow=ap3jobs,apEnv

# get orders by workflows and process result
./operate-workflow.sh get-order "${request_options[@]}" --workflow=ap3jobs,apEnv | jq -r '.orders[] | .orderId'

# get orders by folder and reeturn order id
orders=$(./operate-workflow.sh get-order "${request_options[@]}" --folder=/ap,/ProductDemo | jq -r '.orders[] | .orderId')

# get orders by state and return order id
./operate-workflow.sh get-order "${request_options[@]}" --state=RUNNING,SCHEDULED | jq -r '.orders[] | .orderId'

# get orders, limit result set size and return order id
./operate-workflow.sh get-order "${request_options[@]}" --folder=/ap,/ProductDemo --limit=3 | jq -r '.orders[] | .orderId'

# get orders by regular expression and return order id
./operate-workflow.sh get-order "${request_options[@]}" --folder=/ap,/ProductDemo --regex=Variables | jq -r '.orders[] | .orderId'


# cancel order by state
./operate-workflow.sh cancel-order     "${request_options[@]}" --date-to=-2h --workflow=ap3jobs --state=SCHEDULED,PROMPTING,SUSPENDED,INPROGRESS,RUNNING

# cancel order by state, folder recursively
./operate-workflow.sh cancel-order     "${request_options[@]}" --date-to=-2h --folder=/ap --recursive --state=SCHEDULED,PROMPTING,SUSPENDED,INPROGRESS,RUNNING

# cancel order by order id
./operate-workflow.sh cancel-order     "${request_options[@]}" --order-id="#2024-10-17#T15818656402-root" --force --deep


# suspend order
./operate-workflow.sh suspend-order    "${request_options[@]}" --workflow=ap3jobs

# suspend order and terminate running job
./operate-workflow.sh suspend-order    "${request_options[@]}" --workflow=ap3jobs -force

# suspend order by order id
./operate-workflow.sh suspend-order    "${request_options[@]}" --order-id="#2024-10-17#T15818656402-root" --force --deep


# resume suspended orders
./operate-workflow.sh resume-order     "${request_options[@]}" --workflow=ap3jobs --state=SUSPENDED


# let run waiting order
./operate-workflow.sh letrun-order     "${request_options[@]}" --workflow=ap3jobs --state=WAITING


# transfer order
./operate-workflow.sh transfer-order   "${request_options[@]}" --workflow=ap3jobs

# ------------------------------ Workflows ----------

# suspend workflow
./operate-workflow.sh suspend-workflow "${request_options[@]}" --workflow=ap3jobs


# resume workflow
./operate-workflow.sh resume-workflow  "${request_options[@]}" --workflow=ap3jobs

# ------------------------------ Jobs ----------

# stop jobsNotices
./operate-workflow.sh stop-job         "${request_options[@]}" --workflow=ap3jobs --label=job1,job2

# unstop jobs
./operate-workflow.sh unstop-job       "${request_options[@]}" --workflow=ap3jobs --label=job1,job2


# skip job
./operate-workflow.sh skip-job         "${request_options[@]}" --workflow=ap3jobs --label=job1,job2

# unskip job
./operate-workflow.sh unskip-job       "${request_options[@]}" --workflow=ap3jobs --label=job1,job2

# ------------------------------ Notices ----------

# post notice for current daily plan
./operate-workflow.sh post-notice      "${request_options[@]}" --notice-board=ap3jobs

# post notice for specific daily plan date
./operate-workflow.sh post-notice      "${request_options[@]}" --notice-board=ap3jobs --notice-id=2024-08-26 --notice-lifetime=6h

# get notices by folder
./operate-workflow.sh get-notice       "${request_options[@]}" --folder=/ap --recursive

# delete notice for current daily plan
./operate-workflow.sh delete-notice    "${request_options[@]}" --notice-board=ap3jobs

# delete notice for specific daily plan date
./operate-workflow.sh delete-notice    "${request_options[@]}" --notice-board=ap3jobs --notice-id=2024-08-25,2024-08-26

# delete notices by folder
./operate-workflow.sh delete-notice    "${request_options[@]}" --folder=/ap --recursive

# ------------------------------ Encrypted Passwords ----------

# create Private Key
openssl ecparam -name secp384r1 -genkey -noout -out ./ca/private/encrypt.key

# create Certificate Signing Request
openssl req -new -sha512 -nodes -key ./ca/private/encrypt.key -out ./ca/csr/encrypt.csr -subj "/C=DE/ST=Berlin/L=Berlin/O=SOS/OU=IT/CN=Encrypt"

# create Certificate
openssl x509 -req -sha512 -days 1825 -signkey ./ca/private/encrypt.key -in ./ca/csr/encrypt.csr -out ./ca/certs/encrypt.crt -extfile <(printf "keyUsage=critical,keyEncipherment,keyAgreement\n")

# encrypt
result=$(./operate-workflow.sh encrypt --in=root --cert=./ca/certs/encrypt.crt --java-home=/opt/java/jdk-21)

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password="enc:BEz9kY/z3D5e2RFZKL8m58c9ZpWY68kHGNMS9/Vkbj86aGjgqmMHURquLwIppu78sOZtrNWzpAFswrvvd3fTSGjwFYa1EpU43K5JTDq2x7NdXSE5djHmnJC3BFZikorfj/3W+nPEa7WYjUULS/sz/DBTBb3mWCjQcdP/y2k8QJ3WQzgYiQ== PjHY/QQcs2LYbMivSYjBLg== RjoPa/0xkdSTr8ogXUd3tA==" --key=./ca/private/encrypt.key --java-home=/opt/java/jdk-21 --controller-id=testsuite --ca-cert=./root-ca.crt)

# add ad hoc order
./operate-workflow.sh add-order "${request_options[@]}" --workflow=ap3jobs
