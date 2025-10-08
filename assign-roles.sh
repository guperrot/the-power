#!/bin/bash

.  ./.gh-api-examples.conf

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

# Iterate over each installation
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

  echo "➡️  Assigning roles for $org (install_id: $install_id)"
  GITHUB_TOKEN=$(./ent-call-get-installation-token.sh $install_id | jq -r '.token')

  # Get first org role
  response=$(curl -s -w "\n%{http_code}" \
    -H "X-GitHub-Api-Version: ${github_api_version}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${GITHUB_API_BASE_URL}/orgs/${org}/organization-roles")
  http_code=$(echo "$response" | tail -n1)
  json_body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -lt 300 ]]; then
    first_role_id=$(echo "$json_body" | jq -r '.roles[0].id')
    echo "   ➡️ Got first role id for $org: $first_role_id"
  else
    echo "   ❌ Failed to get roles for $org (HTTP $http_code)"
  fi
  
  # Assign it to the team
  # put /organizations/:organization_id/organization-roles/team/:team_id/:role_id
  response=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "X-GitHub-Api-Version: ${github_api_version}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API_BASE_URL}/orgs/${org}/organization-roles/teams/${team}/${first_role_id}")
  http_code=$(echo "$response" | tail -n1)
  json_body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -lt 300 ]]; then
    echo "   ✅ Assigned role to team $team in $org"
  else
    echo "   ❌ Failed to assign role to team $team in $org (HTTP $http_code)"
  fi

  # Assign to every user, its redundant but we are just using this to scale test performances
  for username in $usernames; do
    (
      response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "${GITHUB_API_BASE_URL}/orgs/${org}/organization-roles/users/${username}/${first_role_id}")
      http_code=$(echo "$response" | tail -n1)
      json_body=$(echo "$response" | sed '$d')
      if [[ "$http_code" -lt 300 ]]; then
        echo "   ✅ Assigned role to $username in $org"
      else
        echo "   ❌ Failed to assign role to $username in $org (HTTP $http_code)"
      fi
    ) &
    sleep 0.019
  done
  wait
done

echo "🎉 Done assigning roles."
