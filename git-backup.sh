#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

# Print a message on std_error
function echo_error() {
  local message="${1}"
  echo "${message}" >&2
}

# Get a value from the config file or exit the application if the value is empty or missing
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
function get_config_value() {
  local file="${1}"
  local key="${2}"
  local value

  yq e "${key}" "${file}"
}

# Handle interrupt and clean up the temporary file
function ctrl_c() {
  echo "trapped ctrl-c"
  rm -rf "${tmp_file}"
  exit 1
}

# Get the link for the next batch of items from the Github REST API
function get_next_link() {
  local header_file="${1}"
  if grep "link:" "${header_file}" | grep -q -E -o "<([^>]+)>; rel=\"next\""; then
    grep -i "link:" "${header_file}" | grep -E -o "<([^>]+)>; rel=\"next\"" | sed -E 's|<([^>]+)>; rel="next"|\1|g'
  else
    echo ""
  fi
}

# declare global variables
declare user
declare token
declare credentials
declare current_folder
declare config_file
declare config_template
declare yq_command
declare backup_folder
declare per_page
declare wait_for
declare global_sync_all_branches
declare -a repositories
declare tmp_file
declare next_link

# assign defaults to global variables
current_folder="$(pwd)"
config_file="./config.yml"
config_template="$(cat <<EOF
version: "1"

# Github configuration
github:
  user: ""
  token: ""
  # Repositories
  type: "all"                     # values: all|public|private
  sync_all_branches: true         # values: true|false (limits synchronization to the default branch)
  repositories: {}                # it can be used to fine-grain the cloning process
#  repositories:                  # use it as a map
#    some_repository:             # each entry has to be the name of a repository
#      sync_all_branches: false   # values: true|false


backup_folder: "./backup"         # the backup folder
per_page: 10                      # items per page to return
wait_for: 10                      # seconds between API requests
EOF
)"

# create the default config file
if [[ ! -f "${config_file}" ]]; then
  echo "Config file missing, creating a new one: '${config_file}'"
  cat <<< "${config_template}" > "${config_file}"
fi

# check required tools
if ! command -v yq &>/dev/null; then
  echo_error "Error: please install yq from https://github.com/mikefarah/yq"
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo_error "Error: please install jq from https://github.com/stedolan/jq"
  exit 1
fi
if ! command -v curl &>/dev/null; then
  echo_error "Error: please install curl (depends on your OS / distribution)"
  exit 1
fi

# check yq version
if yq --version | grep -q ' 3.'; then
  echo_error "yq version >= 4 is required"
  exit 1
fi

backup_folder="$(get_config_value_or_exit "${config_file}" ".backup_folder")"
per_page="$(get_config_value_or_exit "${config_file}" ".per_page")"
wait_for="$(get_config_value_or_exit "${config_file}" ".wait_for")"

user="$(get_config_value_or_exit "${config_file}" ".github.user")"
token="$(get_config_value_or_exit "${config_file}" ".github.token")"
global_sync_all_branches="$(get_config_value_or_exit "${config_file}" ".github.sync_all_branches")"

credentials="${user}:${token}"

# application logic starts here

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

# create backup folder
mkdir -p "${backup_folder}"

# create a tmp file, used to store response headers
tmp_file="$(mktemp)"

# first call to the API
next_link="https://api.github.com/users/${user}/repos?sort=full_name&type=all&per_page=${per_page}&page=1"

# loop till next_link is emty
while [[ ! -z "${next_link}" ]]; do
  # perform the API call with curl and use jq to extract the needed values for each repository
  # reference: https://docs.github.com/en/rest/reference/repos#list-repositories-for-the-authenticated-user
  response="$(curl \
    --silent \
    --dump-header "${tmp_file}" \
    --user "${credentials}" \
    --header "accept: application/vnd.github.v3+json" \
    "${next_link}" \
    | jq --compact-output --raw-output '.[] | {"id": .id, "name": .name, "ssh": .ssh_url, "git_url": .git_url, "https": .clone_url, "default_branch": .default_branch}' \
    | tr -d '\r'
  )"
  # fetch the link for the next batch
  next_link="$(get_next_link "${tmp_file}")"

  # transform the response into an array
  readarray -t repositories < <(echo "${response}")
  # process each repository
  for item in "${repositories[@]}"; do
    # move back to the script's folder
    cd "${current_folder}"

    # extract some info to process the repository
    repository_name="$(jq --compact-output --raw-output '.name' <<< "${item}")"
    repository_ssh="$(jq --compact-output --raw-output '.ssh' <<< "${item}")"
    repository_default_branch="$(jq --compact-output --raw-output '.default_branch' <<< "${item}")"

    # separate the output of each repository
    echo ""
    echo "= Working on '${repository_name}' ="

    # enter the backup folder
    cd "${backup_folder}"
    # perform a git clone of the repository in case it is the first run
    if [[ ! -d "${repository_name}" ]]; then
      git clone "${repository_ssh}"
    fi

    # move into the repository folder
    cd "${repository_name}"
    # fetch new branches and tags and prune the ones removed from the remote
    git fetch origin --prune --prune-tags --tags

    # enter the default branch and synchronize it
    git checkout "${repository_default_branch}"
    git clean -d --force
    git reset --hard "origin/${repository_default_branch}"
    git pull
    # remove any file not tracked by git (just in case)
    # extract remote and local branches
    remote_branches="$(git branch -r | grep -v "origin/HEAD" | sed "s|origin/||g")"
    local_branches="$(git branch --list | sed "s|^*| |g")"

    # prune local branches which don't exist on the remote
    # no quotes around the array
    for local_branch in ${local_branches}; do
      if ! grep --word-regexp --quiet "${local_branch}" <<< "${remote_branches}"; then
        echo "Pruning local branch: '${local_branch}'"
        git branch -D "${local_branch}"
      fi
    done

    # check whether we should synchronize all branches or only the default one
    sync_all_branches="$(get_config_value "${current_folder}/${config_file}" ".github.repositories.${repository_name}.sync_all_branches")"
    if [[ "${global_sync_all_branches}" == "true" ]] && [[ "${sync_all_branches}" != "false" ]]; then
      # we synchronize all branches
      # no quotes around the array
      for remote_branch in ${remote_branches}; do
        # some repos might have branches with the same name but different case, we have to avoid conflicts
        if git branch --list | grep --word-regexp --quiet --ignore-case "${remote_branch}"; then
          # check that remote_branch is an existing branch
          if git branch --list | grep --word-regexp --quiet "${remote_branch}"; then
            # if it is an existing branch, then just check it out
            git checkout "${remote_branch}"
          else
            # branch clash: remote_branch has same name of another branch, but different case
            # it would lead to an error in case of case insensitive file systems
            other_branch="$(git branch --list | grep --word-regexp --only-matching --ignore-case "${remote_branch}")"
            echo "== Skipping '${remote_branch}' as clashes with branch '${other_branch}' =="
            continue
          fi
        else
          # It is a new branch, we check it out and set to track the remote branch
          git checkout -b "${remote_branch}" --track "origin/${remote_branch}"
        fi
        # synchronize the repository
        git reset --hard "origin/${remote_branch}"
        git pull
      done
    else
      echo "Skipping all branch synchronization"
    fi

    # we checkout again the default branch
    git checkout "${repository_default_branch}"
    echo "= Done for '${repository_name}' ="
  done

  # we try not to harass github with too many calls in sequence
  echo "= Sleep for '${wait_for}' seconds ="
  sleep "${wait_for}"
done

# remove the tmp file
rm -rf "${tmp_file}"

# end of the script
echo "All done!"
exit 0
