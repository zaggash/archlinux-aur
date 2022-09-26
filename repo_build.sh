#!/usr/bin/env bash
set -xe
BUILD_OPTION="$1"
PGP_KEY="$2"
SSH_KEY="$3"
LOCAL_REPO_FOLDER="/repo"
REMOTE_REPO_NAME="archlinux-aur"


setupEnv () {
  local repodb="/tmp/$REMOTE_REPO_NAME.db"

  echo "* Prepare Build environment..."
  pacman -Syy --noconfirm --needed git jq openssh rsync docker
  mkdir -p "$LOCAL_REPO_FOLDER/x86_64/"
  ## Download current repo DB
  curl -L "https://github.com/zaggash/$REMOTE_REPO_NAME/releases/download/x86_64/$REMOTE_REPO_NAME.db" --output "$repodb"
  ## setup git stuff
  git submodule update --init --recursive -j 8
  git config advice.detachedHead false
  git config pull.rebase false
  git config user.email "bot@ci"
  git config user.name "BotCI"
  git config push.followTags true
  ## import PGP key
  echo "$PGP_KEY" | base64 -d | gpg --import
  ## Prepare SSH key
  mkdir -p ~/.ssh -m 700
  ## Download Github release binary
  gr_version=$(curl -s https://api.github.com/repos/github-release/github-release/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
  curl -L "https://github.com/github-release/github-release/releases/download/${gr_version}/linux-amd64-github-release.bz2" --output github-release.bz2
  bzip2 -d github-release.bz2 && chmod +x github-release && mv github-release /usr/bin/
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
  local repodb="/tmp/$REMOTE_REPO_NAME.db"
  local platform="$(getPlatform "$pkg_dir")"
  local pkg_name="$(getPackageName "$pkg_dir")"
  local current_version="none"

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
      source <(git --no-pager -C $pkg_dir show master:PKGBUILD)
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

      if [[ -z "$latest_version" ]]
      then
        latest_version="$(curl -skL \
          "https://api.github.com/repos/$repo/tags" |\
          jq -rn 'first( inputs | .[].name)' |\
          sed 's#[^0-9\.]*##g'
          )"
      fi
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
    github.com)
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
    --rm \
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

  repo-add --sign "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.db.tar.gz" "$local_repo_dir"/x86_64/*.pkg.tar.zst
  find "$local_repo_dir/" -type l -delete
  mv "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.db.tar.gz" "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.db"
  mv "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.db.tar.gz.sig" "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.db.sig"
  mv "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.files.tar.gz" "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.files"
  mv "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.files.tar.gz.sig" "$local_repo_dir/x86_64/$REMOTE_REPO_NAME.files.sig"
}

uploadRepo () {
## Upload repo content to the remote webserver
# $1 is true/false to delete non existing local files on the remote webserver

  local delete="$1"
  local local_repo_dir="$LOCAL_REPO_FOLDER"
  local pkg=""
  local github_release_args="\--security-token ${GIT_TOKEN} \--user zaggash \--repo archlinux-aur \--tag x86_64"
  
  case "$delete" in
    true)
      echo "Replacing current repo release."
      # If the release tag exists
      if eval "github-release info $github_release_args"
      then
        # Delete the release
        eval "github-release delete $github_release_args"
      fi
      # Create empty release from the tag
      eval "github-release release \
        $github_release_args \
        --description 'Archlinux x86_64 repo packages'"
      sleep 5 # Wait for the release to be created and available on github
      ;;
    false)
      echo "Skipping, release delete, using same release."
      ;;
    *)
      echo "Error : Upload failed. Unknown option"
      exit 1
      ;;
  esac

  # Upload the packages
  for pkg in $(ls -1 "$local_repo_dir/x86_64/")
  do
    [[ -n $pkg ]] || exit 1
    eval "github-release upload \
      $github_release_args \
      -f $local_repo_dir/x86_64/$pkg \
      -R -n $pkg"
  done
}

prep_full_build () {
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
  local repodb="/tmp/$REMOTE_REPO_NAME.db"
  
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
    cp "$repodb" "$local_repo_root/x86_64/$REMOTE_REPO_NAME.db.tar.gz"
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
