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
# Usage: gitlab_process_repository "path_to_the_config_file" "path_to_the_backup_folder "the_protocol" "sync_all_branches" "json_item"
# Example: gitlab_process_repository "/full/path/to/config.yml" "/full/path/to/backup/folder" "ssh" "true" '{... the json item}'
function gitlab_process_repository() {
  local config_file="${1}"
  local backup_folder="${2}"
  local protocol="${3}"
  local global_sync_all_branches"${4}"
  local item="${5}"

  local repository_name
  local provider

  # extract some info to process the repository
  provider="gitlab"
  repository_name="$(jq --compact-output --raw-output '.name' <<<"${item}")"
  repository_default_branch="$(jq --compact-output --raw-output '.default_branch' <<<"${item}")"
  namespace_full_path="$(jq --compact-output --raw-output '.namespace_full_path' <<<"${item}")"
  path_with_namespace="$(jq --compact-output --raw-output '.path_with_namespace' <<<"${item}")"

  # separate the output of each repository
  echo ""
  echo "= Working on '${repository_name}' ="

  # enter the backup folder
  cd "${backup_folder}"
  # perform a git clone of the repository in case it is the first run
  if [[ ! -d "${backup_folder}/${path_with_namespace}" ]]; then
    # create the project's namespace path
    mkdir -p "${backup_folder}/${namespace_full_path}"
    cd "${backup_folder}/${namespace_full_path}"
    git_clone "${protocol}" "${item}"
  fi

  # move into the repository folder
  cd "${backup_folder}/${path_with_namespace}"

  # synchronize branches
  synchronize_repository "${config_file}" "${provider}" "${repository_name}" "${global_sync_all_branches}" "${repository_default_branch}"
}

# Process all repositories
# Usage: gitlab_process_repositories "path_to_the_config_file" "path_to_the_backup_folder" "path_to_the_config_file"
# Usage: gitlab_process_repositories "/full/path/to/config.yml" "/full/path/to/backup/folder" "/full/path/to/header/tmp.file"
function gitlab_process_repositories() {
  local config_file="${1}"
  local backup_folder="${2}"
  local tmp_file="${3}"

  local user
  local token
  local global_sync_all_branches
  local next_link
  local per_page
  local wait_for
  local response
  local -a repositories
  local protocol

  backup_folder="${backup_folder}/gitlab"

  per_page="$(get_config_value_or_exit "${config_file}" ".per_page")"
  wait_for="$(get_config_value_or_exit "${config_file}" ".wait_for")"

  user="$(get_config_value_or_exit "${config_file}" ".gitlab.user")"
  token="$(get_config_value_or_exit "${config_file}" ".gitlab.token")"
  global_sync_all_branches="$(get_config_value_or_exit "${config_file}" ".gitlab.sync_all_branches")"
  protocol="$(get_config_value_or_exit "${config_file}" ".gitlab.protocol")"

  # first call to the API
  next_link="https://gitlab.com/api/v4/users/${user}/projects?order_by=path&per_page=${per_page}&page=1"

  # loop till next_link is empty
  while [[ -n "${next_link}" ]]; do
    # perform the API call with curl and use jq to extract the needed values for each repository
    # reference: https://docs.gitlab.com/ee/api/projects.html#list-user-projects
    response="$(
      curl \
        --silent \
        --dump-header "${tmp_file}" \
        --header 'accept: application/json' \
        --header "authorization: Bearer ${token}" \
        "${next_link}" |
        jq --compact-output --raw-output '.[] | {"id": .id, "name": .name, "namespace_full_path": .namespace.full_path, "path": .path, "path_with_namespace": .path_with_namespace, "ssh": .ssh_url_to_repo, "https": .http_url_to_repo, "default_branch": .default_branch}' |
        tr -d '\r'
    )"

    # fetch the link for the next batch
    next_link="$(get_next_link_from_header "${tmp_file}")"

    # transform the response into an array
    readarray -t repositories < <(echo "${response}")
    # process each repository
    for item in "${repositories[@]}"; do
      gitlab_process_repository "${config_file}" "${backup_folder}" "${protocol}" "${global_sync_all_branches}" "${item}"
    done

    # we try not to harass github with too many calls in sequence
    echo "= Sleep for '${wait_for}' seconds ="
    sleep "${wait_for}"
  done
}
