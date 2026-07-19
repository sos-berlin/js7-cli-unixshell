#!/bin/bash

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password=root --controller-id=testsuite --ca-cert=./root-ca.crt)

# ------------------------------ Export/Import ----------

# export workflows
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --path=/ap/ap3jobs,/ap/Agent/apRunAsUser --type=WORKFLOW

# export draft schedules
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --path=/ap/Agent/apAgentSchedule01,/ap/Agent/apAgentSchedule02 --type=SCHEDULE --no-released

# export objects from folder
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --folder=/ap --recursive

# export objects from folder using relative path
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --folder=/ap/Agent --recursive --use-short-path

# export objects from folder, limiting object type and validity, feeding audit log
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --folder=/ap --recursive --type=WORKFLOW,NOTICEBOARD --no-invalid --audit-message="export to prod"

# export objects from change including referencing and referenced objects
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --change=CH-TestRepo-01

# export objects from change including referencing and referenced objects limited to folder
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --change=CH-TestRepo-01 --folder=/TestRepo

# export objects from change including referenced objects
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --change=CH-TestRepo-01 --no-referencing

# export objects from change including referencing objects
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --change=CH-TestRepo-01 --no-references


# import objects
./deploy-workflow.sh import "${request_options[@]}" --file=export.zip --overwrite

# import objects with suffix
./deploy-workflow.sh import "${request_options[@]}" --file=export.zip --folder=/ap --suffix=ap22

# ------------------------------ Import and Deploy ----------

# export and import/deploy for high security level
request_options=(--url=https://centostest-primary.sos:6446 --user=ap-si-ecdsa --password=ap-si-ecdsa --controller-id=training --ca-cert=./training-ca.crt)

# export objects from folder for signing
./deploy-workflow.sh export        "${request_options[@]}" --file=export.zip --folder=/myFolder --recursive --for-signing

# import/deploy objects
./deploy-workflow.sh import-deploy "${request_options[@]}" --file=import-from-signing.zip

# ------------------------------ Deploy/Revoke ----------

# deploy objects from folder
./deploy-workflow.sh deploy "${request_options[@]}" --folder=/ap/Agent --recursive --date-from=now

# deploy workflows by object path and type
./deploy-workflow.sh deploy "${request_options[@]}" --path=/ap/ap3jobs,/ap/apEnv --type=WORKFLOW --date-from=now

# deploy objects by change including referencing objects and referenced objects
./deploy-workflow.sh deploy "${request_options[@]}" --change=CH-TestRepo-01

# deploy objects by change excluding referencing objects
./deploy-workflow.sh deploy "${request_options[@]}" --change=CH-TestRepo-01 --no-referencing

# deploy objects by change excluding referenced objects
./deploy-workflow.sh deploy "${request_options[@]}" --change=CH-TestRepo-01 --no-references


# revoke objects from folder
./deploy-workflow.sh revoke "${request_options[@]}" --folder=/ap/Agent --recursive 

# revoke workflows
./deploy-workflow.sh revoke "${request_options[@]}" --path=/ap/ap3jobs,/ap/apEnv --type=WORKFLOW

# ------------------------------ Release/Recall ----------

# release objects from folder
./deploy-workflow.sh release "${request_options[@]}" --folder=/ap/Agent --recursive --date-from=now

# release schedules
./deploy-workflow.sh release "${request_options[@]}" --path=/ap/Agent/apAgentSchedule01,/ap/Agent/apAgentSchedule02 --type=SCHEDULE --date-from=now

# release objects by change including referencing objects and referenced objects
./deploy-workflow.sh release "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01

# release objects by change excluding referencing objects
./deploy-workflow.sh release "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-referencing

# release objects by change excluding referenced objects
./deploy-workflow.sh release "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-references


# recall objects from folder
./deploy-workflow.sh recall  "${request_options[@]}" --folder=/ap/Agent --recursive 

# recall schedules
./deploy-workflow.sh recall  "${request_options[@]}" --path=/ap/Agent/apAgentSchedule01,/ap/Agent/apAgentSchedule02 --type=SCHEDULE

# ------------------------------ Store/Remove/Restore/Delete ----------

# store object
./deploy-workflow.sh store   "${request_options[@]}" --path=/ap/NewFolder01/NewWorkflow01 --type=WORKFLOW --file=NewWorkflow01.workflow.json

# remove object, update daily plan
./deploy-workflow.sh remove  "${request_options[@]}" --path=/ap/NewFolder01/NewWorkflow01 --type=WORKFLOW --date-from=now

# remove objects from folder, update daily plan
./deploy-workflow.sh remove  "${request_options[@]}" --folder=/ap/NewFolder01 --date-from=now


# restore object from trash, using suffix for restored objectd
./deploy-workflow.sh restore "${request_options[@]}" --path=/ap/NewFolder01/NewWorkflow01 --type=WORKFLOW --new-path=/ap/NewFolder01/NewWorkflow01 --suffix=restored

# delete object from trash
./deploy-workflow.sh delete  "${request_options[@]}" --path=/ap/NewFolder01/NewWorkflow01 --type=WORKFLOW

# delete objects from trash by folder
./deploy-workflow.sh delete  "${request_options[@]}" --folder=/ap/NewFolder01

# ------------------------------ Encrypted Passwords ----------

# create Private Key
openssl ecparam -name secp384r1 -genkey -noout -out ./ca/private/encrypt.key

# create Certificate Signing Request
openssl req -new -sha512 -nodes -key ./ca/private/encrypt.key -out ./ca/csr/encrypt.csr -subj "/C=DE/ST=Berlin/L=Berlin/O=SOS/OU=IT/CN=Encrypt"

# create Certificate
openssl x509 -req -sha512 -days 1825 -signkey ./ca/private/encrypt.key -in ./ca/csr/encrypt.csr -out ./ca/certs/encrypt.crt -extfile <(printf "keyUsage=critical,keyEncipherment,keyAgreement\n")

# encrypt
result=$(./deploy-workflow.sh encrypt --in=root --cert=./ca/certs/encrypt.crt --java-home=/opt/java/jdk-21)

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=root --password="enc:BEXbHYacGkm/2bcx5NjYgLnsoxVMt1lpD3k+Dgc34aaTZIXnjbcatL5IQysNx1SUcnSNC6cr/Msfpv1Gau8znH6NiXAt08sAWTRpXQ5+YIALHl+ENt89lSfDCvfrEek82oJTAXStDHyfYMvYlJQYlb4BoelnHo7MagPiQP/E1ukqLI6S2w== VLJEgsBsKJedUUlSsMCCyQ== 7ajEelvz8w6HMvmFiGBIFA==" --key=./ca/private/encrypt.key --java-home=/opt/java/jdk-21 --controller-id=testsuite --ca-cert=./root-ca.crt)

# export workflows
./deploy-workflow.sh export "${request_options[@]}" --file=export.zip --path=/ap/ap3jobs,/ap/Agent/apRunAsUser --type=WORKFLOW
