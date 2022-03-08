# Git Backup

Quick and dirty script in bash to locally clone all personal repositories from online providers (Github only for the moment).

It can be used in case your government decides to block access to the rest of internet (and Github).

## Features and whatnot

Features:
- automatic git clone of all your public and private repositories
- automatic branch synchronization with remote ones
- branch and tag pruning

Planned improvements (not yet implemented):
- handle Bitbucket and other online git repository providers
- handle organization repos (Github)
- handle submodules
- handle branches with same name but different case
- handle git clone via https
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

1. generate a personal Github token (it will only be used to connect to Github)
   1. log in to Github
   2. open https://github.com/settings/tokens
   3. generate a new token with these scopes:
      - read:org (needed to access organization's repositories)
      - repo (needed to access private repositories)
2. run the `./git-backup.sh` script
3. it will generate a `config.yml` file
4. edit the `config.yml` file
   1. set your username
   2. set your personal token
   3. choose whether to clone all repositories or only public or private ones
   4. choose whether to synchronize all branches by default or only the default one (applied to all repositories)
   5. choose whether to fine grain the synchronization and clone only the default branch for a specific repository
   6. set the path of the backup folder (can be relative to the script folder)
   7. set how many repositories to retrieve for each API call (max 50)
   8. set how many seconds to wait between each API call
5. run the `./git-backup.sh` script
6. if needed, block the execution with ctrl-c

## Miscellaneous

Done with 💙️ in 🇪🇺

We ❤️ ️🇺🇦 people

We ❤️️ 🇷🇺 people

**🖕 war!**
