#!/bin/bash

# set common options for connection to the JS7 REST Web Service
request_options=(--url=http://joc-2-0-primary.sos:7446 --user=ap --password=ap --controller-id=testsuite --ca-cert=./root-ca.crt)

# ------------------------------ Credentials ----------

# get credentials
./deploy-git.sh get-credentials    "${request_options[@]}"

# store credentials
./deploy-git.sh store-credentials  "${request_options[@]}" --server=github.com --user-account=community \
                                    --user-name="Community" --user-mail="community@example.com" \
                                    --user-private-key=/var/sos-berlin.com/js7/joc/resources/joc/repositories/private/sos-community.rsa

# delete credentials
./deploy-git.sh delete-credentials "${request_options[@]}" --server=github.com

# ------------------------------ Items ----------

# list items from JOC Cockpit rollout repository
./deploy-git.sh list-item  "${request_options[@]}" --folder=/TestRepo --recursive


# store inventory items to JOC Cockpit rollout repository: folder
./deploy-git.sh store-item "${request_options[@]}" --folder=/TestRepo --recursive

# store inventory items to JOC Cockpit rollout repository: object path and type
./deploy-git.sh store-item "${request_options[@]}" --path=/TestRepo/03_VariablesPassing/jdwVariablesAdHoc-repo --type=WORKFLOW

# store inventory items to JOC Cockpit local repository: object path and type
./deploy-git.sh store-item "${request_options[@]}" --path=/TestRepo/03_VariablesPassing/jdjVariablesJobResource --type=JOBRESOURCE --local

# store inventory items to JOC Cockpit rollout repository: object path and type
./deploy-git.sh store-item "${request_options[@]}" --path=/TestRepo/51_JobTemplates/51_JobTemplate --type=JOBTEMPLATE

# store inventory items to JOC Cockpit rollout repository: change objects including any referencing and referenced objects
./deploy-git.sh store-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01

# store inventory items to JOC Cockpit rollout repository: change objects excluding referencing objects
./deploy-git.sh store-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-referencing

# store inventory items to JOC Cockpit rollout repository: change objects excluding referenced objects
./deploy-git.sh store-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-references


# update inventory items from JOC Cockpit rollout repository: folder
./deploy-git.sh update-item "${request_options[@]}" --folder=/TestRepo

# update inventory items from JOC Cockpit local repository: folder
./deploy-git.sh update-item "${request_options[@]}" --folder=/TestRepo --local

# update inventory items from JOC Cockpit rollout repository: path and object type
./deploy-git.sh update-item "${request_options[@]}" --path=/TestRepo/03_VariablesPassing/jdwVariablesAdHoc-repo --type=WORKFLOW

# update inventory items from JOC Cockpit rollout repository: change objects including any referencing and referenced objects
./deploy-git.sh update-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01

# update inventory items from JOC Cockpit rollout repository: change objects excluding referencing objects
./deploy-git.sh update-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-referencing

# update inventory items from JOC Cockpit rollout repository: change objects excluding referenced objects
./deploy-git.sh update-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-references


# delete items from JOC Cockpit rollout repository: folder
./deploy-git.sh delete-item "${request_options[@]}" --folder=/TestRepo/03_VariablesPassing

# delete items from JOC Cockpit rollout repository: object path and type
./deploy-git.sh delete-item "${request_options[@]}" --path=/TestRepo/03_VariablesPassing/jdwVariablesAdHoc-repo --type=WORKFLOW

# delete items from JOC Cockpit rollout repository: object path and type
./deploy-git.sh delete-item "${request_options[@]}" --path=/TestRepo/51_JobTemplates/51_JobTemplate --type=JOBTEMPLATE

# delete items from JOC Cockpit local repository: object path and type
./deploy-git.sh delete-item "${request_options[@]}" --path=/TestRepo/03_VariablesPassing/jdjVariablesJobResource --type=JOBRESOURCE --local

# delete items from JOC Cockpit rollout repository: change objects including any referencing and referenced objects
./deploy-git.sh delete-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01

# delete items from JOC Cockpit rollout repository: change objects excluding referencing objects
./deploy-git.sh delete-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-referencing

# delete items from JOC Cockpit rollout repository: change objects excluding referenced objects
./deploy-git.sh delete-item "${request_options[@]}" --folder=/TestRepo --change=CH-TestRepo-01 --no-references

# ------------------------------ Git Operations ----------

# clone remote Git repository to JOC Cockpit rollout repository
./deploy-git.sh clone    "${request_options[@]}" --folder=/TestRepo --remote-url="git@github.com:sos-berlin/js7-demo-inventory-rollout-test"

# checkout branch to JOC Cockpit rollout repository
./deploy-git.sh checkout "${request_options[@]}" --folder=/TestRepo --branch=v1

# add items to JOC Cockpit rollout repository
./deploy-git.sh add      "${request_options[@]}" --folder=/TestRepo

# commit changes to JOC Cockpit rollout repository and keep commit hash
hash=$(./deploy-git.sh commit   "${request_options[@]}" --folder=/TestRepo --message="v.1.23.34")

# push changes from JOC Cockpit rollout repository to remote repository
./deploy-git.sh push     "${request_options[@]}" --folder=/TestRepo

# pull changes from remote repository to JOC Cockpit rollout repository
./deploy-git.sh pull     "${request_options[@]}" --folder=/TestRepo

