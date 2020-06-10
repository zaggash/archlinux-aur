#!/usr/bin/env bash
set -xe

PKG_DIR=$1
[[ ! -d "$PKG_DIR" ]] && echo "$PKG_DIR is not a valid package folder." && exit 1

pkg_name=$(basename "$PKG_DIR")

if [[ -f "$PKG_DIR/.git" ]]
then
  platform="submodule"
else
  platform="$(sed -n 's/^url="\(.*\)"/\1/p' "$PKG_DIR/PKGBUILD" | cut -d'/' -f 3)"
fi

case "$platform" in
  submodule)
    current_version=$(git -C "$PKG_DIR" log -1 --pretty=format:%H)
    git -C "$PKG_DIR" pull -q
    latest_version=$(git -C "$PKG_DIR" log -1 --pretty=format:%H)
    ;;
  github.com)
    repo=$(sed -n 's/^url="\(.*\)"/\1/p' "$PKG_DIR/PKGBUILD" | cut -d'/' -f 4-5)
    current_version=$(sed -n 's/^pkgver=\(.*\)/\1/p' "$PKG_DIR/PKGBUILD")
    latest_version=$(curl -skL \
      "https://api.github.com/repos/$repo/releases/latest" |\
      jq -r '.tag_name' |\
      sed 's#[^0-9\.]*##g'
    )
    sed -i "s#^pkgver.*#pkgver=$latest_version#" "$PKG_DIR/PKGBUILD"
    ;;
  *)
    echo "$platform is unknown !"
    exit 1
    ;;
esac

if [[ "$latest_version" != "$current_version" ]]
then
  echo "New version found !"
  touch commit_msg
  touch new_versions_tag
  echo "$pkg_name" >> new_versions_tag
  git add "$PKG_DIR"
  echo " * Bump $pkg_name version from $current_version to $latest_version" >> commit_msg
else
  echo "No update."
fi


exit 0
