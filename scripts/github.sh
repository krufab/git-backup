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

# Process a single repository
# Usage: github_process_repository "path_to_the_config_file" "path_to_the_backup_folder "the_protocol" "sync_all_branches" "json_item"
# Example: github_process_repository "/full/path/to/config.yml" "/full/path/to/backup/folder" "ssh" "true" '{... the json item}'
function github_process_repository() {
  local config_file="${1}"
  local backup_folder="${2}"
  local protocol="${3}"
  local global_sync_all_branches"${4}"
  local item="${5}"

  local repository_name
  local provider

  # extract some info to process the repository
  provider="github"
  repository_name="$(jq --compact-output --raw-output '.name' <<<"${item}")"
  repository_default_branch="$(jq --compact-output --raw-output '.default_branch' <<<"${item}")"

  # separate the output of each repository
  echo ""
  echo "= Working on '${repository_name}' ="

  # enter the backup folder
  cd "${backup_folder}"
  # perform a git clone of the repository in case it is the first run
  if [[ ! -d "${repository_name}" ]]; then
    git_clone "${protocol}" "${item}"
  fi

  # move into the repository folder
  cd "${repository_name}"

  # synchronize branches
  synchronize_repository "${config_file}" "${provider}" "${repository_name}" "${global_sync_all_branches}" "${repository_default_branch}"
}

# Process all repositories
# Usage: github_process_repositories "path_to_the_config_file" "path_to_the_backup_folder" "path_to_the_config_file"
# Usage: github_process_repositories "/full/path/to/config.yml" "/full/path/to/backup/folder" "/full/path/to/header/tmp.file"
function github_process_repositories() {
  local config_file="${1}"
  local backup_folder="${2}"
  local tmp_file="${3}"

  local user
  local token
  local credentials
  local global_sync_all_branches
  local next_link
  local per_page
  local wait_for
  local response
  local -a repositories
  local protocol

  backup_folder="${backup_folder}/github"

  per_page="$(get_config_value_or_exit "${config_file}" ".per_page")"
  wait_for="$(get_config_value_or_exit "${config_file}" ".wait_for")"

  user="$(get_config_value_or_exit "${config_file}" ".github.user")"
  token="$(get_config_value_or_exit "${config_file}" ".github.token")"
  global_sync_all_branches="$(get_config_value_or_exit "${config_file}" ".github.sync_all_branches")"
  protocol="$(get_config_value_or_exit "${config_file}" ".github.protocol")"

  credentials="${user}:${token}"

  # first call to the API
  next_link="https://api.github.com/users/${user}/repos?sort=full_name&type=all&per_page=${per_page}&page=1"

  # loop till next_link is empty
  while [[ -n "${next_link}" ]]; do
    # perform the API call with curl and use jq to extract the needed values for each repository
    # reference: https://docs.github.com/en/rest/reference/repos#list-repositories-for-the-authenticated-user
    response="$(
      curl \
        --silent \
        --dump-header "${tmp_file}" \
        --user "${credentials}" \
        --header "accept: application/vnd.github.v3+json" \
        "${next_link}" |
        jq --compact-output --raw-output '.[] | {"id": .id, "name": .name, "ssh": .ssh_url, "git": .git_url, "https": .clone_url, "default_branch": .default_branch}' |
        tr -d '\r'
    )"

    # fetch the link for the next batch
    next_link="$(get_next_link_from_header "${tmp_file}")"

    # transform the response into an array
    readarray -t repositories < <(echo "${response}")
    # process each repository
    for item in "${repositories[@]}"; do
      github_process_repository "${config_file}" "${backup_folder}" "${protocol}" "${global_sync_all_branches}" "${item}"
    done

    # we try not to harass github with too many calls in sequence
    echo "= Sleep for '${wait_for}' seconds ="
    sleep "${wait_for}"
  done
}
