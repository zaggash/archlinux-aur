#!/usr/bin/env bash

## execute the script against the good repo
grep -sq archlinux-aur .git/config
if [[ $? -ne 0 ]]
  then
    echo "Not in archlinux-aur Repo !"
    exit 10
fi

## check number of arguments
[[ $# -ne 1 ]] && echo "One submodule is needed as argument !" && exit 10

! [[ $1 =~ https?://.*\.git ]] && echo "The URL is not a Git repo" && exit 11

## set argument as named variable
GIT_URL="$1"
MODULE="$(echo $GIT_URL | sed 's#.*/\(.*\).git#\1#')"

## run the script
echo -e "\n * Updating the local repo"
git pull

echo -e "\n * Adding submodule $MODULE"
git submodule add "$GIT_URL" "$MODULE"

echo -e "\n * add commit message"
git add .git/
git add "$MODULE"
git commit -m "add $MODULE AUR [skip ci]"

echo -e "\n ----------"
echo "** $MODULE added, if everything is fine, please proceed to the 'git push' **"
echo " ----------"
