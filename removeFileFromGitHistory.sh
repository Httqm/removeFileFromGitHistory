#!/usr/bin/env bash
# TODO:
#	- display 'n MB saved' at the end
#	- NB: looks like cloning already gets a smaller repository (TBC)
#	- remove 'shrinkDotGit.sh' (just 'git rm' : I want it to stay in the history)

absolutePathToGitRepoRootDir="$HOME/CDK"
gitFilterRepo="$HOME/apps/git-filter-repo/git-filter-repo"

#backupFileToRemove=0
backupFileToRemove=1

#simulate=0		# when not simulating, this script will be reset to its latest committed version
simulate=1

#verbose=0
verbose=1

#tmpBaseDir="/run/user/$(id -u)"	# 800MB only on Arkan
tmpBaseDir='/run/shm/'				# 4GB on Arkan


# declared here to make them global

dataFile=$(basename "$0" '.sh')'.txt'
# list of files to remove from the Git history
#	1 filename per line
#	paths are relative to the root of the repository base directory : "$absolutePathToGitRepoRootDir"
#	lines starting with '#' are comments and are ignored
# expected file name : "<nameOfThisScript>.txt"

workDir=''
output=''


confirmContinueWithoutSimulating() {
	[ "$simulate" -eq 0 ] && {
		cat <<-EOF

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
	output='/dev/null'
	[ "$verbose" == '1' ] && output='/dev/stdout'

	# if simulate==1, work on a clone of the repo
	workDir="$absolutePathToGitRepoRootDir"
	[ "$simulate" -ne 0 ] && {
		workDir=$(mktemp -d -p "$tmpBaseDir" tmp.gitClone.XXXXXXXX)
		git clone --no-local "$absolutePathToGitRepoRootDir" "$workDir" || { echo 'Press any key'; read; exit 1; }
		}
	}


getDirSize() {
	local directory="$1"
	du -sh "$directory" | cut -f1
	}


countOccurrencesOfFileToRemove() {
	local fileToRemove=$1
	nbOccurrences=$(git log --oneline "$fileToRemove" | wc -l)
	currentFileSize=$(ls -lh "$fileToRemove" | cut -d' ' -f5)
	cat <<-EOF

	Working on '$fileToRemoveFromGitHistory' :
	- occurrences : $nbOccurrences
	- current size : $currentFileSize
	EOF
	}


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
	cat <<-EOF
	SIZE BEFORE :	$sizeBefore
	SIZE AFTER  :	$sizeAfter
	EOF
	}


doFinalCleaning() {
	# the '--aggressive' directive
	#	- makes the script WAY slower
	#	- does not save that much space :-/
	# TODO: correct way to do this : https://stackoverflow.com/questions/5613345/how-to-shrink-the-git-folder/8483112#8483112
	git gc --prune=now
	}


main() {
	confirmContinueWithoutSimulating
	checkGitFilterRepoIsAvailable
	initializeVariables
	cd "$workDir"

	while read fileToRemoveFromGitHistory; do
		[[ "$fileToRemoveFromGitHistory" =~ ^(#|$) ]] && continue
		sizeBefore=$(getDirSize '.')
		countOccurrencesOfFileToRemove "$fileToRemoveFromGitHistory"
		makeBackupOfFileToRemove "$fileToRemoveFromGitHistory"
		removeFileFromHistory "$fileToRemoveFromGitHistory"
		checkFileWasRemoved "$fileToRemoveFromGitHistory"
		restoreFileToRemove "$fileToRemoveFromGitHistory"
		sizeAfter=$(getDirSize '.')
		displayRepoSize "$sizeBefore" "$sizeAfter"
	done < "$dataFile"

	doFinalCleaning
	}

main
