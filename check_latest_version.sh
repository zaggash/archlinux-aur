#!/usr/bin/env bash
set -e

ENV_CI=$1

source "$ENV_CI"

case "$platform" in
  github)
    latest_version=$(curl -skL \
      "https://api.github.com/repos/$project/releases/latest" |\
      jq -r '.tag_name' |\
      sed 's#[^0-9\.]*##g'
    )
    ;;
  *)
    echo "$platform is unknown !"
    exit 1
    ;;
esac

echo "$latest_version"
exit 0
