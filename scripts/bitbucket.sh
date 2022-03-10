#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

declare scripts_folder
# Relative to this script
scripts_folder="$(dirname "$(readlink --canonicalize "${BASH_SOURCE[0]}")")"
# shellcheck source=scripts/common.sh
source "${scripts_folder}/common.sh"

# Get the link for the next batch of items or return an empty string
function bitbucket_get_next_link() {
  local response="${1}"

  jq --compact-output --raw-output '.next // ""' <<<"${response}" 2>/dev/null
}

# Process a single repository
# Usage: bitbucket_process_repository "path_to_the_config_file" "path_to_the_backup_folder "the_protocol" "sync_all_branches" "json_item"
# Example: bitbucket_process_repository "/full/path/to/config.yml" "/full/path/to/backup/folder" "ssh" "true" '{... the json item}'
function bitbucket_process_repository() {
  local config_file="${1}"
  local backup_folder="${2}"
  local protocol="${3}"
  local global_sync_all_branches"${4}"
  local item="${5}"

  local repository_name
  local provider

  # extract some info to process the repository
  provider="bitbucket"
  repository_name="$(jq --compact-output --raw-output '.name' <<<"${item}")"
  repository_default_branch="$(jq --compact-output --raw-output '.default_branch' <<<"${item}")"
  full_name="$(jq --compact-output --raw-output '.full_name' <<<"${item}")"
  workspace_slug="$(jq --compact-output --raw-output '.workspace_slug' <<<"${item}")"

  # separate the output of each repository
  echo ""
  echo "= Working on '${repository_name}' ="

  # enter the backup folder
  cd "${backup_folder}"
  # perform a git clone of the repository in case it is the first run
  if [[ ! -d "${full_name}" ]]; then
    # create the project's namespace path
    mkdir -p "${backup_folder}/${workspace_slug}"
    cd "${backup_folder}/${workspace_slug}"
    git_clone "${protocol}" "${item}"
  fi

  # move into the repository folder
  cd "${backup_folder}/${full_name}"

  # synchronize branches
  synchronize_repository "${config_file}" "${provider}" "${repository_name}" "${global_sync_all_branches}" "${repository_default_branch}"
}

# Process all repositories
# Usage: bitbucket_process_repositories "path_to_the_config_file" "path_to_the_backup_folder" "path_to_the_config_file"
# Usage: bitbucket_process_repositories "/full/path/to/config.yml" "/full/path/to/backup/folder" "/full/path/to/header/tmp.file"
function bitbucket_process_repositories() {
  local config_file="${1}"
  local backup_folder="${2}"
  local _="${3}"

  local user
  local token
  local credentials
  local global_sync_all_branches
  local next_link
  local next_link_workspaces
  local per_page
  local wait_for
  local response
  local -a repositories
  local -a workspaces
  local protocol

  backup_folder="${backup_folder}/bitbucket"

  per_page="$(get_config_value_or_exit "${config_file}" ".per_page")"
  wait_for="$(get_config_value_or_exit "${config_file}" ".wait_for")"

  user="$(get_config_value_or_exit "${config_file}" ".bitbucket.user")"
  token="$(get_config_value_or_exit "${config_file}" ".bitbucket.token")"
  global_sync_all_branches="$(get_config_value_or_exit "${config_file}" ".bitbucket.sync_all_branches")"
  protocol="$(get_config_value_or_exit "${config_file}" ".bitbucket.protocol")"

  credentials="${user}:${token}"

  # first call to the API
  next_link_workspaces="https://api.bitbucket.org/2.0/user/permissions/workspaces?sort=workspace.slug&pagelen=${per_page}"

  # loop till next_link_workspaces is empty
  while [[ -n "${next_link_workspaces}" ]]; do
    # perform the API call with curl and use jq to extract the needed values for each repository
    # reference: https://docs.github.com/en/rest/reference/repos#list-repositories-for-the-authenticated-user
    response="$(
      curl \
        --silent \
        --user "${credentials}" \
        --header 'Accept: application/json' \
        "${next_link_workspaces}" |
        tr -d '\r'
    )"
    # fetch the link for the next batch
    next_link_workspaces="$(bitbucket_get_next_link "${response}")"

    # transform the response into an array
    readarray -t workspaces < <(jq --compact-output --raw-output '.values[] | .workspace.slug' <<<"${response}")
    # process each workspace
    for workspace in "${workspaces[@]}"; do
      next_link="https://api.bitbucket.org/2.0/repositories/${workspace}?sort=full_name&pagelen=${per_page}"
      response="$(
        curl \
          --silent \
          --user "${credentials}" \
          --header 'Accept: application/json' \
          "${next_link}" |
          tr -d '\r'
      )"
      next_link="$(bitbucket_get_next_link "${response}")"

      # transform the response into an array
      readarray -t repositories < <(jq --compact-output --raw-output '.values[] | {"id": .uuid, "name": .name, "ssh": .links.clone[] | select(.name == "ssh").href, "https": .links.clone[] | select(.name == "https").href, "default_branch": .mainbranch.name, "full_name": .full_name, "workspace_slug": .workspace.slug}' <<<"${response}")
      # process each repository
      for item in "${repositories[@]}"; do
        bitbucket_process_repository "${config_file}" "${backup_folder}" "${protocol}" "${global_sync_all_branches}" "${item}"
      done

      # we try not to harass github with too many calls in sequence
      echo "= Sleep for '${wait_for}' seconds ="
      sleep "${wait_for}"
    done
  done
}
