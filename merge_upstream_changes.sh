#!/usr/bin/env bash 
#
# Soft Fork Bot
#
# This script keeps a soft fork compatible with the upstream repository.
# It automatically pulls changes from upstream and opens an MR.
# Inspired by https://rpadovani.com/open-mr-gitlab-ci
#
# Copyright (C) 2024 Open Energy Transition
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Algorithm:
# if MR doesnt exist && branch doesnt exist: create branch, merge upstream, create MR
# if MR doesnt exist && branch exists: reset branch, merge upstream, create MR
# if MR exists && branch doesnt exist: impossible
# if MR exists && branch exists: warn user to resolve existing MR, or manually update

set -eux

git remote add -f upstream ${UPSTREAM_REPO}
git remote update  # TODO only fetch UPSTREAM_BRANCH?

# Configure commit author details
git config --global user.email "<>" # This commit author has no email
git config --global user.name "Upstream Merge Bot"
git config --list

# Extract the host where the server is running, and add the URL to the APIs
[[ $HOST =~ ^https?://[^/]+ ]] && HOST="${BASH_REMATCH[0]}/api/v4/projects/"

# Check if MR exists with source_branch = CHANGE_BRANCH
LISTMR=`curl --silent "${HOST}${CI_PROJECT_ID}/merge_requests?state=opened" --header "PRIVATE-TOKEN:${PRIVATE_TOKEN}"`;
NUM_MR=`echo ${LISTMR} | grep -o "\"source_branch\":\"${CHANGE_BRANCH}\"" | wc -l`;

FORCE_PUSH=""

# Check if CHANGE_BRANCH exists already:
if git branch --remote | grep origin/${CHANGE_BRANCH} > /dev/null; then
  # If MR doesn't exist, then it is a stale branch so reset it:
  if [ ${NUM_MR} -eq "0" ]; then
    git checkout -b ${CHANGE_BRANCH} --track origin/${CHANGE_BRANCH}
    git reset --hard origin/${MAIN_BRANCH}
    FORCE_PUSH="--force"  # hard reset will require a force push later
  else
    echo There already exists an MR for ${CHANGE_BRANCH}.
    echo Please resolve any conflicts in the MR and merge it in and re-run this pipeline.
    echo Alternatively, you can also merge both origin/${MAIN_BRANCH} and 
    echo upstream/${UPSTREAM_BRANCH} into ${CHANGE_BRANCH} manually and then merge it in.
    exit 1
  fi
else
  # Branch doesn't exist, so create one at MAIN_BRANCH:
  git checkout --track origin/${MAIN_BRANCH}
  git checkout -b ${CHANGE_BRANCH}
fi

COMMIT_MSG="Merge changes from upstream repo ${UPSTREAM_REPO}"

# Now try to merge upstream changes
OLD_HEAD=`git rev-parse HEAD`
if git merge upstream/${UPSTREAM_BRANCH} -m "${COMMIT_MSG}"; then
  # Merge succeeded or already up-to-date
  NEW_HEAD=`git rev-parse HEAD`
  if [ "$OLD_HEAD" == "$NEW_HEAD" ]; then
    echo No new changes upstream
    exit
  fi
else
  # Conflicts or error, assume conflicts and create a commit:
  # --all commits the unresolved merge conflicts, to be resolved by user
  git commit --verbose --all --message "${COMMIT_MSG}"
fi

# Push the updated branch:
git remote set-url origin https://${GITLAB_USER}:${PRIVATE_TOKEN}@${THIS_REPO}.git
git push -v --set-upstream origin ${FORCE_PUSH} ${CHANGE_BRANCH}

# If no MR found, let's create a new one
if [ ${NUM_MR} -eq "0" ]; then
  # The description of our new MR:
  BODY="{
      \"id\": ${CI_PROJECT_ID},
      \"source_branch\": \"${CHANGE_BRANCH}\",
      \"target_branch\": \"${MAIN_BRANCH}\",
      \"description\": \"This MR was automatically created to bring in the changes from the upstream repository ${UPSTREAM_REPO}.\n\nIMPORTANT: Do NOT squash merge this MR, otherwise any merge conflicts resolved in this MR will have to be resolved again.\",
      \"squash\": false,
      \"remove_source_branch\": true,
      \"title\": \"${COMMIT_MSG}\"
  }";
  # NOTE: JSON doesn't like trailing commas!

  curl --fail -X POST "${HOST}${CI_PROJECT_ID}/merge_requests" \
      --header "PRIVATE-TOKEN:${PRIVATE_TOKEN}" \
      --header "Content-Type: application/json" \
      --data "${BODY}";

  echo Opened a new merge request for upstream changes
else
  echo Pushed new upstream changes to existing MR
fi