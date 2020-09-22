#!/usr/bin/env bash
set -xe
BUILD_OPTION="$1"
PGP_KEY="$2"
SSH_KEY="$3"
LOCAL_REPO_FOLDER="/repo"
REMOTE_REPO_NAME="zaggarch-repo"


setupEnv () {
  pacman -Syy --noconfirm --needed git jq openssh rsync docker
  mkdir -p "$LOCAL_REPO_FOLDER/x86_64/"
  ## setup git stuff
  git submodule update --init --recursive -j 8
  git config advice.detachedHead false
  git config pull.rebase false
  git config user.email "bot@ci"
  git config user.name "BotCI"
  ## import PGP key
  echo "$PGP_KEY" | base64 -d | gpg --import
  ## Add my Repo
  pacman-key --init
  curl -sL 'https://keybase.io/apinon/pgp_keys.asc?fingerprint=54231a262e8bf5501c6945d275bcc090ca185c57' | pacman-key -a -
  pacman-key --lsign-key 54231a262e8bf5501c6945d275bcc090ca185c57
  echo "
[$REMOTE_REPO_NAME]
Server = https://sourceforge.net/projects/\$repo/files/\$arch
SigLevel = Required
" | tee -a /etc/pacman.conf
  pacman -Syy
  ## Prepare SSH key
  mkdir -p ~/.ssh -m 700
  echo "web.sourceforge.net,216.105.38.21 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCwsY6sZT4MTTkHfpRzYjxG7mnXrGL74RCT2cO/NFvRrZVNB5XNwKNn7G5fHbYLdJ6UzpURDRae1eMg92JG0+yo=" > ~/.ssh/known_hosts
  echo -e "$SSH_KEY" > ~/.ssh/key
  chmod 600 ~/.ssh/key
  eval $(ssh-agent)
  ssh-add ~/.ssh/key
}

getPlatform () {
## Get the package source package.
# $1 is the package folder

  local pkg_dir="$1"
  local platform=""

  if [[ -f "$pkg_dir/.git" ]]
  then
    platform="submodule"
  else
    source "$pkg_dir/PKGBUILD"
    platform="$(echo $url | cut -d'/' -f 3)"
  fi

  echo "$platform"
}


getPackageName () {
## get package name
# $1 is the package folder

  local pkg_dir="$1"
  local pkg_name=""

  source "$pkg_dir/PKGBUILD"
  pkg_name="$pkgname"
  echo "$pkg_name"
}

getCurrentVersion () {
## get current version of the package
# $1 is the package folder
# 
  local pkg_dir="$1"
  local repodb="/var/lib/pacman/sync/$REMOTE_REPO_NAME.db"
  local platform="$(getPlatform "$pkg_dir")"
  local pkg_name="$(getPackageName "$pkg_dir")"
  local current_version=""

  # Return package version or blank if not in the repo
  current_version=$(tar --exclude='*/*' -tf "$repodb" | sed -n "s@$pkg_name-\(.*\)/@\1@p")
  case "$platform" in
    submodule)
      echo "$current_version"
      ;;
    github.com)
      echo "$current_version" | cut -d'-' -f 1
      ;;
    *)
      echo "$platform is unknown !"
      exit 1
      ;;
  esac
}

getLatestVersion () {
## get latest version of the package
# $1 is the package folder

  local pkg_dir="$1"
  local platform="$(getPlatform "$pkg_dir")"
  local repo=""
  local latest_version=""

  case "$platform" in
    submodule)
      source <(git --no-pager -C ./lens/ show master:PKGBUILD)
      latest_version="$pkgver-$pkgrel"
      ;;
    github.com)
      source "$pkg_dir/PKGBUILD"
      repo=$(echo "$url" | cut -d'/' -f 4-5)
      latest_version="$(curl -skL \
        "https://api.github.com/repos/$repo/releases/latest" |\
        jq -r '.tag_name' |\
        sed 's#[^0-9\.]*##g'
        )"
      ;;
    *)
      echo "$platform is unknown !"
      exit 1
      ;;
  esac
  echo "$latest_version"
}

setLatestVersion () {
## set latest version in PKGBUILD
# $1 is the package folder

  local pkg_dir="$1"
  local platform="$(getPlatform "$pkg_dir")"
  local latest_version=""

  case "$platform" in
    submodule)
      git -C "$pkg_dir" checkout master
      git -C "$pkg_dir" pull
      ;;
    github.com)
      latest_version=$(getLatestVersion "$pkg_dir")
      sed -i "s#^pkgver.*#pkgver=$latest_version#" "$pkg_dir/PKGBUILD"
      ;;
    *)
      echo "$platform is unknown !"
      exit 1
      ;;
  esac
}

checkUpdate () {
## check if repo is updated
# $1 is the package folder

  local pkg_dir="$1"
  local platform="$(getPlatform "$pkg_dir")"
  local to_update="false"

  case "$platform" in
    submodule)
      [ $(git -C "$pkg_dir" rev-parse HEAD) != $(git -C "$pkg_dir" rev-parse master@{upstream}) ] && to_update="true"
      ;;
    github)
      [[ $(getCurrentVersion "$pkg_dir") != $(getLatestVersion "$pkg_dir") ]] && to_update="true"
      ;;
    *)
      echo "$platform is unknown !"
      exit 1
      ;;
  esac
  echo "$to_update"
}

buildPackage () {
## build package from package dir
# $1 is package dir

  local pkg_dir="$1"
  local old_dir=$(pwd)

  cd "$pkg_dir"
  docker run \
    -e EXPORT_PKG=true \
    -e CHECKSUM_SRC=true \
    -e PGPKEY="$PGP_KEY" \
    -e PACKAGER="Alexandre Pinon <github@ziggzagg.fr>" \
    -v "$(pwd):/pkg" zaggash/arch-makepkg || exit 1
  cd "$old_dir"
}

moveBuildPackages () {
## Move build packages and sig to dest_dir

  local local_repo_dir="$LOCAL_REPO_FOLDER"

  for sig in $(find ./* -type f -name "*.pkg.tar.zst.sig")
  do
    pkg=${sig%".sig"}
    mv "$pkg"* "$local_repo_dir/x86_64/"
  done
}

genRepoDB () {
## Generate the Arch repo DB

  local local_repo_dir="$LOCAL_REPO_FOLDER"

  repo-add --sign "$local_repo_dir/x86_64/zaggarch-repo.db.tar.gz" "$local_repo_dir"/x86_64/*.pkg.tar.zst
  find "$local_repo_dir/" -type l -delete
  mv "$local_repo_dir/x86_64/zaggarch-repo.db.tar.gz" "$local_repo_dir/x86_64/zaggarch-repo.db"
  mv "$local_repo_dir/x86_64/zaggarch-repo.db.tar.gz.sig" "$local_repo_dir/x86_64/zaggarch-repo.db.sig"
  mv "$local_repo_dir/x86_64/zaggarch-repo.files.tar.gz" "$local_repo_dir/x86_64/zaggarch-repo.files"
  mv "$local_repo_dir/x86_64/zaggarch-repo.files.tar.gz.sig" "$local_repo_dir/x86_64/zaggarch-repo.files.sig"
}

uploadRepo () {
## Upload repo content to the remote webserver
# $1 is true/false to delete non existing file on the remote webserver

  local rsync_delete="$1"
  local local_repo_dir="$LOCAL_REPO_FOLDER"
  local rsync_option=""

  if [[ "$rsync_delete" == "true" ]]
  then
    rsync_option="-avhP -I --delete"
  else
    rsync_option="-avhP -I"
  fi

  eval "rsync -e 'ssh -o StrictHostKeyChecking=yes' \
      $rsync_option \
      $local_repo_dir/x86_64 zaggash@web.sourceforge.net:/home/frs/project/zaggarch-repo/"
}

prep_full_build() {
## Full repo build logic

  local pkg_dir="$1"
  local pkg_name="$(getPackageName $pkg_dir)"
  echo "$pkg_name" | tee -a pkgs_to_build
}

prep_incr_build () {
## Incremental repo building logic
# $1 is package dir

  local pkg_dir="$1"
  local pkg_name="$(getPackageName $pkg_dir)"
  local current_v="$(getCurrentVersion $pkg_dir)"
  local latest_v="$(getLatestVersion $pkg_dir)"
  local new_update="$(checkUpdate $pkg_dir)"

  if [[ "$new_update" == "true" ]]
  then
    echo "New version found !"
    echo "$pkg_name" | tee -a pkgs_to_build
    echo " * Bump $pkg_name version from $current_v to $latest_v" | tee -a commit_msg
    setLatestVersion "$pkg_dir"
    git add "$pkg_dir"
  else
    echo "No updates."
  fi
}

main () {
## Main routines to build the repo 
# $1 allow to choose between build options : full/incremental

  local option="$1"
  local local_repo_root="$LOCAL_REPO_FOLDER"
  
  for pkgbuild in $(find ./* -type f -name "PKGBUILD")
  do
    local pkg_dir=$(dirname $pkgbuild)
    case "$option" in
      full)
        prep_full_build "$pkg_dir"
        ;;
      incremental)
        prep_incr_build "$pkg_dir"
        ;;
    esac
  done
  if [[ -f commit_msg ]]
  then
    sed -i '1i[skip ci] Packages updated:' commit_msg
    git commit -F commit_msg
    cp /var/lib/pacman/sync/zaggarch-repo.db "$local_repo_root/x86_64/zaggarch-repo.db.tar.gz"
  fi

  if [[ -f pkgs_to_build ]]
  then
    for pkg in $(cat pkgs_to_build)
    do
      buildPackage "$pkg"
    done
    moveBuildPackages
    genRepoDB
    case "$option" in
      full)
        uploadRepo "true"
        ;;
      incremental)
        uploadRepo "false"
        ;;
    esac
  fi
}

#---------------------# Main #--------------------#
## Call to the main routine


setupEnv
main "$BUILD_OPTION"
