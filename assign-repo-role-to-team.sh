#!/bin/bash

.  ./.gh-api-examples.conf

# https://docs.github.com/en/rest/teams/teams?apiVersion=2022-11-28#add-or-update-team-repository-permissions

if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN is not set, please provide a PAT with admin:enterprise scope."
  exit 1
fi

if [ -n "$1" ]; then
  ending_org=$1
fi

if [ -n "$2" ]; then
  starting_org=$2
fi

list_enterprise_team_members_output=$(./list-enterprise-team-members.sh "$team")
if [ $? -ne 0 ]; then
  echo $list_enterprise_team_members_output
  exit 1
fi
usernames=$list_enterprise_team_members_output
app_installs=$(./tiny-list-app-installations.sh)

repo=${repo:-"private-repo-1"}

# Sort app installations by account login and iterate
echo "$app_installs" | jq -c '. | sort_by(.account.login) | .[]' | while read -r install; do
  install_id=$(echo "$install" | jq -r '.id')
  org=$(echo "$install" | jq -r '.account.login')
  if [ -z "$org" ] || [ "$org" = "null" ]; then
    continue
  fi

  if [ -n "$starting_org" ]; then
    if [[ "$org" < "$starting_org" ]]; then
      continue
    fi
  fi

  if [ -n "$ending_org" ]; then
    if [[ "$org" > "$ending_org" ]]; then
      continue
    fi
  fi

  echo "➡️   Assigning repo permissions for $org (install_id: $install_id)"
  GITHUB_TOKEN=$(./ent-call-get-installation-token.sh  $install_id | jq -r '.token')

  response=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"permission\":\"triage\"}" \
  "$GITHUB_API_BASE_URL/orgs/$org/teams/$team/repos/$org/$repo")
  http_code=$(echo "$response" | tail -n1)
  json_body=$(echo "$response" | sed '$d')

  if [[ "$http_code" == "201" ]] || [[ "$http_code" == "204" ]]; then
    echo "   ✅ Repo permissions assigned to $team"
  else
    echo "   ❌ Failed to assign repo permissions (HTTP $http_code) for $team"
    echo "   Response: $json_body"
  fi
  wait
done

echo "🎉 Done assigning repo permissions."
