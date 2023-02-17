#!/usr/bin/env bash
# TODO:
#	- display 'n MB saved' at the end
#	- remove 'shrinkDotGit.sh' (just 'git rm' : I want it to stay in the history)
#
# final path (?) : ~/CDK/Doc/static/shell/removeFileFromGitHistory.sh

absolutePathToGitRepoRootDir="$HOME/CDK"
#absolutePathToGitRepoRootDir="/run/user/1000/tmp.gitclone"

#fileToRemoveFromHistoryRelativeToGitRepoRootDir='things/passwords/p455.kdbx'	# 80MB saved
fileToRemoveFromHistoryRelativeToGitRepoRootDir='Doc/static/webArticles/Git - Présentation basique et non-exhaustive.pdf'	# 9MB saved


#backupFileToRemove=0
backupFileToRemove=1

#simulate=0		# when not simulating, this script will be reset to its latest committed version
simulate=1

#verbose=0
verbose=1


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


# with this script, I may want to :
#	- completely make a file disappear from the history
#	- OR remove old versions of a file while still keeping the current version.
#		- this is why I make a backup
#		- once the script has run, the 'restored' file is unknown to Git and must be added + committed as an 'initial version'
makeBackupOfFileToRemove() {
	local fileToRemove=$1
	[ "$backupFileToRemove" -eq 1 ] && cp "$fileToRemove" "$tmpBaseDir"
	}


restoreFileToRemove() {
	local fileToRemove=$1

	# Git dislikes empty directories and may have deleted the one storing "$fileToRemove"
	# if this file was the only one in there
	mkdir -p "$(dirname ${fileToRemove})"

	[ "$backupFileToRemove" -eq 1 ] && mv "$tmpBaseDir/$(basename "$fileToRemove")" "$fileToRemove"
	git add "$fileToRemove"
	git commit -m "initial version after wiping history"
	}


# '--force' must be passed to 'git filter-repo' to let it work in "real" mode.
# TODO: hardcode OR pass this parameter without hardcoding (?)
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

	makeBackupOfFileToRemove "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"

	removeFileFromHistory "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"
	checkFileWasRemoved "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"
	doFinalCleaning
	sizeAfter=$(getDirSize '.')

	restoreFileToRemove  "$fileToRemoveFromHistoryRelativeToGitRepoRootDir"

	displayRepoSize "$sizeBefore" "$sizeAfter"
	}


main
