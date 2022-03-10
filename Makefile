.PHONY: shellcheck
shellcheck:
	shellcheck --check-sourced --external-sources --source-path=SCRIPTDIR,./scripts *.sh scripts/*.sh
