#!/usr/bin/env bash

## execute the script again the good repo
grep -sq archlinux-aur .git/config
if [[ $? -ne 0 ]]
  then
    echo "Not in archlinux-aur Repo !"
    exit 10
fi

help() {
  # Show Help
  echo "This script remove a submodule from the repo and commit the change. "
  echo "    Syntax: $0 [Submodule name]"
  echo ""
}

## check number of arguments
[[ $# -ne 1 ]] && help && echo "One submodule is needed as argument !" && exit 10

## set argument as named variable
MODULE=$1

## check if argument is a submodule
grep -qs "$MODULE.git" .gitmodules
[[ $? -ne 0 ]] && help && echo "Submodule is not found !" && exit 30

## run the script
echo -e "\n * Updating the local repo"
git pull
git submodule update --init --recursive
echo -e "\n * Removing the submodule $MODULE"
git submodule deinit "$MODULE"
git rm "$MODULE"
echo -e "\n * add commit message"
git commit -m "feat(package): remove submodule $MODULE"
echo -e "\n * removing local reference of the submodule"
rm -rf ".git/modules/$MODULE"
echo -e "\n ----------"
echo "** $MODULE removed, if everything is fine, please proceed to the 'git push' **"
echo " ----------"
