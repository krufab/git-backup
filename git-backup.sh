#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

declare base_folder
# Relative to this script
base_folder="$(dirname "$(readlink --canonicalize "${BASH_SOURCE[0]}")")"
# shellcheck source=scripts/common.sh
source "${base_folder}/scripts/common.sh"
# shellcheck source=scripts/bitbucket.sh
source "${base_folder}/scripts/bitbucket.sh"
# shellcheck source=scripts/github.sh
source "${base_folder}/scripts/github.sh"
# shellcheck source=scripts/gitlab.sh
source "${base_folder}/scripts/gitlab.sh"

# Handle interrupt and clean up the temporary file
function ctrl_c() {
  echo "trapped ctrl-c"
  rm -rf "${tmp_file}"
  exit 1
}

# declare global variables
declare config_file
declare config_template

declare tmp_file
declare backup_folder
declare provider_enabled

# assign defaults to global variables
config_file="${base_folder}/config.yml"
config_template="$(
  cat <<EOF
version: "1"

# Bitbucket configuration
bitbucket:
  enabled: true                   # values: true|false
  # account
  user: ""
  token: ""                       # application password (account read, repositories read permissions)
  protocol: "ssh"                 # values: https|ssh (default ssh)
  # repositories
  sync_all_branches: true         # values: true|false (default true) limits synchronization to the default branch
  repositories: {}                # it can be used to fine-grain the cloning process
#  repositories:                  # use it as a map
#    some_repository:             # each entry has to be the name of a repository
#      sync_all_branches: false   # values: true|false

# Github configuration
github:
  enabled: true                   # values: true|false
  # account
  user: ""
  token: ""                       # personal access token
  protocol: "ssh"                 # values: git|https|ssh (default ssh)
  # repositories
  sync_all_branches: true         # values: true|false (default true) limits synchronization to the default branch
  repositories: {}                # it can be used to fine-grain the cloning process
#  repositories:                  # use it as a map
#    some_repository:             # each entry has to be the name of a repository
#      sync_all_branches: false   # values: true|false

# Gitlab configuration
gitlab:
  enabled: true                   # values: true|false
  # account
  user: ""
  token: ""                       # application password
  protocol: "ssh"                 # values: https|ssh (default ssh)
  # repositories
  sync_all_branches: true         # values: true|false (default true) limits synchronization to the default branch
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
  cat <<<"${config_template}" >"${config_file}"
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
backup_folder="$(readlink --canonicalize "${backup_folder}")"
# application logic starts here

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

# create a tmp file, used to store response headers
tmp_file="$(mktemp)"

# process bitbucket if enabled
provider_enabled="$(get_config_value_or_exit "${config_file}" ".bitbucket.enabled")"
if [[ "${provider_enabled}" == "true" ]]; then
  echo "= Processing Bitbucket repositories ="
  mkdir -p "${backup_folder}/bitbucket"
  bitbucket_process_repositories "${config_file}" "${backup_folder}" "${tmp_file}"
fi

# process github if enabled
provider_enabled="$(get_config_value_or_exit "${config_file}" ".github.enabled")"
if [[ "${provider_enabled}" == "true" ]]; then
  echo "= Processing Github repositories ="
  mkdir -p "${backup_folder}/github"
  github_process_repositories "${config_file}" "${backup_folder}" "${tmp_file}"
fi

# process gitlab if enabled
provider_enabled="$(get_config_value_or_exit "${config_file}" ".gitlab.enabled")"
if [[ "${provider_enabled}" == "true" ]]; then
  echo "= Processing Gitlab repositories ="
  mkdir -p "${backup_folder}/gitlab"
  gitlab_process_repositories "${config_file}" "${backup_folder}" "${tmp_file}"
fi

# remove the tmp file
rm -rf "${tmp_file}"

# end of the script
echo "All done!"
exit 0
