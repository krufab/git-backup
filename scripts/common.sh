#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

# Print a message on std_error
# Usage: echo_error "the message to print"
# Example: echo_error "Error: something happened"
function echo_error() {
  local message="${1}"

  echo "${message}" >&2
}

# Get a value from the config file or exit the application if the value is empty or missing
# Usage: get_config_value_or_exit "path_to_the_config_file" "the_key_to_fetch"
# Example: get_config_value_or_exit "/full/path/to/config.yml" ".github.token"
function get_config_value_or_exit() {
  local file="${1}"
  local key="${2}"

  local value

  value="$(yq e "${key}" "${file}")"
  if [[ -z "${value}" ]]; then
    echo_error "Error: ${key} value is empty"
    exit 1
  fi
  echo "${value}"
}

# Get a value from the config file
# Usage: get_config_value "path_to_the_config_file" "the_key_to_fetch"
# Usage: get_config_value "/full/path/to/config.yml" ".github.repositories"
function get_config_value() {
  local file="${1}"
  local key="${2}"

  yq e "${key}" "${file}"
}

# Get the link for the next batch from the link header or return an empty string
# Usage: get_next_link_from_header "path_to_the_header_file"
# Usage: get_next_link_from_header "/full/path/to/header/tmp.file"
function get_next_link_from_header() {
  local header_file="${1}"

  grep -i "link:" "${header_file}" | grep -E -o "<([^>]+)>; rel=\"next\"" | sed -E 's|<([^>]+)>; rel="next"|\1|g' || echo ""
}

# Perform the git clone action
# Usage: git_clone "the_protocol" "json_item"
# Usage: git_clone "ssh" '{... the json item}'
function git_clone() {
  local protocol="${1}"
  local item="${2}"

  local key
  local url

  case "${protocol}" in
  git)
    key=".git"
    ;;
  https)
    key=".https"
    ;;
  ssh)
    key=".ssh"
    ;;
  *)
    echo_error "Error: wrong protocol: '${protocol}'"
    exit 1
    ;;
  esac

  url="$(jq --compact-output --raw-output "${key}" <<<"${item}")"

  git clone "${url}"
}

# Prune local branches which don't exist on the remote
# Usage: prune_local_branches "list_of_remote_branches"
# Usage: prune_local_branches "main a-branch another-branch"
function prune_local_branches() {
  local remote_branches="${1}"

  local local_branches

  local_branches="$(git branch --list | sed "s|^*| |g")"

  # no quotes around the array
  for local_branch in ${local_branches}; do
    if ! grep --word-regexp --quiet "${local_branch}" <<<"${remote_branches}"; then
      echo "== Pruning local branch: '${local_branch}' =="
      git branch -D "${local_branch}"
    fi
  done
}

# Synchronize a branch
# Usage: synchronize_branch "the_branch_name"
# Usage: synchronize_branch "main"
function synchronize_branch() {
  local branch="${1}"

  git checkout "${branch}"
  git reset --hard "origin/${branch}"
  git pull
}

# Synchronize a repository
# Usage: synchronize_repository "path_to_the_config_file" "the_provider" "the_repository_name" "sync_all_branches" "the_default_branch"
# Example: synchronize_repository "/full/path/to/config.yml" "github" "a-repository" "true" "main"
function synchronize_repository() {
  local config_file="${1}"
  local provider="${2}"
  local repository_name="${3}"
  local global_sync_all_branches="${4}"
  local repository_default_branch="${5}"

  local remote_branches
  local sync_all_branches
  local other_branch

  # fetch new branches and tags and prune the ones removed from the remote
  git fetch origin --prune --prune-tags --tags

  # enter the default branch and synchronize it
  synchronize_branch "${repository_default_branch}"

  # extract remote branches
  remote_branches="$(git branch -r | grep -v "origin/HEAD" | sed "s|origin/||g")"

  prune_local_branches "${remote_branches}"

  # check whether we should synchronize all branches or only the default one
  sync_all_branches="$(get_config_value "${config_file}" ".${provider}.repositories.${repository_name}.sync_all_branches")"
  if [[ "${global_sync_all_branches}" == "true" ]] && [[ "${sync_all_branches}" != "false" ]]; then
    # we synchronize all branches
    # no quotes around the array
    for remote_branch in ${remote_branches}; do
      # some repos might have branches with the same name but different case, we have to avoid conflicts
      if ! git branch --list | grep --word-regexp --quiet --ignore-case "${remote_branch}"; then
        # It is a new branch, we check it out and set to track the remote branch
        git checkout -b "${remote_branch}" --track "origin/${remote_branch}"
      else
        # check that remote_branch is an existing branch
        if ! git branch --list | grep --word-regexp --quiet "${remote_branch}"; then
          # branch clash: remote_branch has same name of another branch, but different case
          # it would lead to an error in case of case insensitive file systems
          other_branch=$(git branch --list | grep --word-regexp --only-matching --ignore-case "${remote_branch}")
          echo "== Skipping '${remote_branch}' as clashes with branch '${other_branch}' =="
          continue
        fi
      fi
      # synchronize the repository
      synchronize_branch "${remote_branch}"
    done
  else
    echo "Skipping all branches synchronization"
  fi

  # we checkout again the default branch
  git checkout "${repository_default_branch}"
  echo "= Done for '${repository_name}' ="
}
