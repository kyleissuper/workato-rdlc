#!/bin/bash
#
# Workato recipe development lifecycle functions
#
#
######################################################
#
# Environment variables assumed:
# 
#   # Get these from workato.com/users/current/edit
#   $wDevAuth = "user_email={}&&user_token={}"
#   $wStgAuth = "user_email={}&&user_token={}"
#   $wPrdAuth = "user_email={}&&user_token={}"
# 
#   # API token for test suite endpoint
#   $wStgApiToken = "..."
#
# Hardcoded values in this version:
#   Workato Folder IDs, recipe IDs, and test suite
#   endpoint URL
#
######################################################


# Push to branch in Github from Workato package
pullWorkato() {
  local branchName=${1}
  local commitComment=${2}
  local wManifestID=${3}
  local authString=$wDevAuth

  # New clean branch
  git pull origin master
  git checkout -b $branchName
  git rm -rf *

  # Get package from Workato
  local packageID="$(curl -X POST https://www.workato.com/api/packages/export/$wManifestID?$authString | jq '.id')"
  echo "Package ID" $packageID
  while true; do
    sleep 2
    local packageStatus=$(curl https://www.workato.com/api/packages/$packageID?$authString | jq -r '.status')
    if [ $packageStatus == "completed" ]; then
      break
    fi
    echo "Waiting for export to complete..."
    echo $packageStatus
  done
  wget -O tmp.zip https://www.workato.com/api/packages/$packageID/download?$authString
  unzip -o tmp.zip && rm tmp.zip

  # Push it
  git add *
  git commit -m "$commitComment"
  git push origin $branchName
  git checkout master
  git branch -D $branchName
}

# Import local repo to Workato staging environment,
# run tests, and then push to production if passed.
deploy() {
  echo "Pushing to staging."
  pushRepoToWorkato 130690 $wStgAuth 

  local passedTests=$(curl -XGET -H "API-TOKEN: $wStgApiToken" \
    "https://apim.workato.com/test-suites/hr" | jq -r ".passed_all_tests")

  if [ $passedTests == "true" ]; then
    echo "Tests passed! Pushing to production now."
    pushRepoToWorkato 130699 $wPrdAuth
    echo "Successfully pushed to production."
  else
    echo "Tests failed. More details in Staging at workato.com/recipes/1001012"
  fi
}

# Push the local repo to Workato
pushRepoToWorkato() {
  local folderID=${1}    # Workato folder ID
  local authString=${2}  # Workato platform API auth
  
  # Update local
  git checkout master
  git pull origin master

  # Zip, push, delete zip
  zip -r $PWD.zip $PWD
  local packageID=$(curl --data-binary @$PWD.zip \
    -H "Content-Type: application/octet-stream" \
    -X POST \
    "https://www.workato.com/api/packages/import/$folderID?restart_recipes=true&$authString" \
    | jq ".id")
  while true; do
    sleep 2
    local packageStatus=$(curl https://www.workato.com/api/packages/$packageID?$authString | jq -r '.status')
    if [ $packageStatus == "completed" ]; then
      break
    elif [ $packageStatus == "failed" ]; then
      echo "Import failed. More details at workato.com/import_targets"
      exit
    fi
    echo "Waiting for import to complete..."
    echo $packageStatus
  done
  echo "Imported successfully!"
  rm $PWD.zip
}
