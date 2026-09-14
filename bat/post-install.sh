#!/usr/bin/env bash
###################################################################
# Script Name : bat/post-install.sh
# Description : Register the themes shipped in this package with bat
# Args : path to the installed bat binary, path to this package directory
# Author : Barnabás Vass
###################################################################
#
# install-tools.sh runs this after linking the config. bat only picks up
# .tmTheme files from its config directory once its cache has been rebuilt.

bat=${1:-bat}

[[ -x $bat ]] || bat=$(command -v bat) || {
    echo "bat is not available, cannot rebuild its theme cache" >&2
    exit 1
}

"$bat" cache --build >/dev/null 2>&1 || {
    echo "bat cache --build failed" >&2
    exit 1
}
