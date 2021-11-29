#!/usr/bin/env bash
# TODO:
#	- display 'n MB saved' at the end
#	- remove 'shrinkDotGit.sh' (just 'git rm' : I want it to stay in the history)
#
# final path (?) : ~/CDK/Doc/static/shell/removeFileFromGitHistory.sh

absolutePathToGitRepoRootDir="$HOME/CDK"
#absolutePathToGitRepoRootDir="/run/user/1000/tmp.gitclone"

fileToRemoveFromHistoryRelativeToGitRepoRootDir='things/passwords/p455.kdbx'	# 80MB saved
#fileToRemoveFromHistoryRelativeToGitRepoRootDir='Doc/static/webArticles/Git - Présentation basique et non-exhaustive.pdf'	# 9MB saved


#verbose=0
verbose=1

#simulate=0
simulate=1


gitFilterRepo="$HOME/apps/git-filter-repo/git-filter-repo"

#tmpBaseDir="/run/user/$(id -u)"	# 800MB only on Arkan
tmpBaseDir='/run/shm/'				# 4GB on Arkan


# declared here to make them global
workDir=''
output=''


confirmContinueWithoutSimulating() {
	[ "$simulate" -eq 0 ] && {
		cat <<EOF

	This script is NOT running in simulation mode and WILL CHANGE data.

	Press :
		- ENTER  to continue
		- CTRL-c to abort
EOF
		read;
		}
	}


checkGitFilterRepoIsAvailable() {
	"$gitFilterRepo" --version &>/dev/null || { echo "Looks like 'git filter-repo' is not installed."; exit 1; }
	}


initializeVariables() {
	workDir="$absolutePathToGitRepoRootDir"

	output='/dev/null'
	[ "$verbose" == '1' ] && output='/dev/stdout'

	# if simulate==1, work on a clone of the repo :
	[ "$simulate" -ne 0 ] && {
		workDir=$(mktemp -d -p "$tmpBaseDir" tmp.gitClone.XXXXXXXX)
		git clone --no-local "$absolutePathToGitRepoRootDir" "$workDir" || { echo 'Press any key'; read; exit 1; }
		}
	}


getDirSize() {
	local directory="$1"
	du -sh "$directory" | cut -f1
	}


removeFileFromHistory() {
	local fileToRemove=$1
	"$gitFilterRepo" --invert-paths --path "$fileToRemove" 1>"$output" || { echo 'Houston, we have a problem.'; exit 1; }
	}


checkFileWasRemoved() {
	local fileToRemove=$1
	nbEntriesInLog=$(git log --oneline -- "$fileToRemove" | wc -l)
	[ "$nbEntriesInLog" -gt 0 -o -f "$fileToRemove" ] && { echo "Looks like '$fileToRemove' is still there."; exit 1; }
	}


displayRepoSize() {
	local sizeBefore=$1
	local sizeAfter=$2
	cat << EOF
SIZE BEFORE :	$sizeBefore
SIZE AFTER  :	$sizeAfter
EOF
	}


doFinalCleaning() {
	git gc --prune=now
	}


main() {
	confirmContinueWithoutSimulating
	checkGitFilterRepoIsAvailable
	initializeVariables
	cd "$workDir"
	sizeBefore=$(getDirSize '.')
	removeFileFromHistory "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"
	checkFileWasRemoved "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"
	doFinalCleaning
	sizeAfter=$(getDirSize '.')
	displayRepoSize "$sizeBefore" "$sizeAfter"
	}


main
