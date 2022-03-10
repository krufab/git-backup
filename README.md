# Git Backup

Beautiful script in bash to locally clone all the repositories from online providers (Bitbucket, Github and Gitlab) that
your account has access to (the public & privates ones, plus the ones of your organization / workspace etc).

It can be used in case your government decides to block access to the rest of internet.

Or in case foreign companies apply restrictions and prevent you from accessing your code form one day to another.

## Why this project?

Git is a distributed version control system, and it is quite normal for developers to already have a local copy of the
code they are working on. However, organizations with many users or very active developers might have tens or more
repositories, which might not all be up-to-date on the local computer.
This script facilitates their retrieval in case of need: it is quite simple to check out and synchronize 5-10
repositories once, but it might take long if the number increases.

Moreover, this script can be triggered by a cron job and run periodically.

## Features and whatnot

Features:

- automatic git clone of all your public and private repositories
- automatic branch synchronization with remote ones
- branch and tag pruning
- works with Bitbucket, Github and Gitlab
- handle git clone via https

Planned improvements (not yet implemented):

- create a Docker container
- handle organization repos (Github)
- handle submodules
- handle branches with same name but different case
- handle proxy
- add tests

It will **not**:

- push branches to a new remote repository (no migration)
- synchronize remote branches with local ones (one way change: remote -> local))

## Requirements

The following tools are requird to run the script

1. jq (get it from: https://github.com/stedolan/jq)
2. yq >= 4 (get it from: https://github.com/mikefarah/yq)
3. curl
4. bash >= 5

## High level process description

The script will perform the following tasks:

1. generate a config file if it is not there
2. read the config file
3. perform some sanity checks on the required parameters and tools
4. create the backup folder if it does not exist
5. request the list of the user's repositories using the provider's REST API
6. process each entry
   1. perform a full clone of a repository if it is a new one
   2. fetch changes and prune old branches and tags
   3. synchronize the default branch from the remote one
   4. synchronize all other branches from the remote ones

## Usage

1. generate a personal token or application password (see below)
2. run the `./git-backup.sh` script
3. it will generate a `config.yml` file
4. edit the `config.yml` file, for each provider
   1. set the provider enabled (true) if you want to use it
   2. set your username
   3. set your personal token or application password
   4. choose whether to synchronize all branches by default or only the default one (applied to all repositories)
   5. choose whether to fine grain the synchronization and clone only the default branch for a specific repository
   6. set the path of the backup folder (can be relative to the script folder)
   7. set how many repositories to retrieve for each API call (max 50)
   8. set how many seconds to wait between each API call
5. run the `./git-backup.sh` script
6. if needed, block the execution with ctrl-c

## How to request access token for REST API requests

- How to generate an application password with **Bitbucket**
  1. log in to Bitbucket
  2. open https://bitbucket.org/account/settings/app-passwords/
  3. generate a new app password with these permissions:
     - account read
     - repositories read
- How to generate a personal token with **Github**
  1. log in to Github
  2. open https://github.com/settings/tokens
  3. generate a new token with these scopes:
     - read:org (needed to access organization's repositories)
     - repo (needed to access private repositories)
- How to generate an application password with **Gitlab**
  1. log in to Gitlab
  2. open https://gitlab.com/-/profile/personal_access_tokens
  3. generate a new personal access token with these scopes
     - read_api

## Miscellaneous

Done with 💙️ in 🇪🇺

We ❤️ ️🇺🇦 people

We ❤️️ 🇷🇺 people

**🖕 the war!**
