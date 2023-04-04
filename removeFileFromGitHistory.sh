#!/usr/bin/env bash

set -u
set -o pipefail

# initial and default values of CLI parameters
absolutePathToGitRepoRootDir=''
gitRepoDir='./'
simulate=1
verbose=1


# global variables
fileToRemoveFromGitHistory=''
keepLatestVersion=''
output=''
tmpBaseDir='/run/shm/'
workDir=''


# list of files + parameters
# format :
#	<filename>;<keepLatestVersion>
#	- <filename> :
#		- path of the file to remove from Git
#		- relative to the root of the repository "$absolutePathToGitRepoRootDir"
#	- <keepLatestVersion> :
#		- 0 : completely wipe <filename> from the repository
#		- 1 : delete history of <filename> + commit its latest version back
#			  into the repository as a "new initial version"
#	- lines starting with '#' are comments and are ignored
#
# expected <dataFile> file name : "<nameOfThisScript>.txt"
# Retrieving the absolute path of this file is made necessary by the "simulate" mode where
# we 'cd' into a temporary directory and can't refer to this file with a relative path
dataFile=$(dirname $(readlink -f "$0"))/$(basename "$0" '.sh')'.txt'



error() {
	echo -e "\033[1;31mERROR\033[0m: $1"
	}


info() {
	echo -e "\033[1;36mINFO\033[0m: $1"
	}


# TODO: specify file on the CLI or list of files in .txt file
usage() {
	cat <<-EOUSAGE

	$0: Remove the specified file(s) from the Git history

	USAGE:
	    $0 [OPTIONS]

	options:
	  -g <dir>, --git-repo-dir <dir>      Root directory of the Git repository
	  -h, --help                          Display this help message and exit
	  -s <0|1>, --simulate <0|1>          Simulation mode: work on a clone of the repository (default: 1)
	  -v <0|1>, --verbose <0|1>           Verbose mode (default: 1)
	EOUSAGE
	}


warnEmptyValue() {
	local currentFlag=$1
	local value=$2
	[ -z "$value" ] && {
		error "No value given for '$currentFlag'"
		usage
		exit 1
		}
	}


getCliParameters() {
	[ "$#" -eq 0 ] && {
		error 'no option given'
		usage
		exit 1
		}

	while [ "$#" -gt 0 ]; do
		case "$1" in
			-g | --git-repo-dir)
				shift; gitRepoDir="${1:-}"; warnEmptyValue '-g' "$gitRepoDir"; shift ;;
			-h | --help)
				usage; exit 0 ;;
			-s | --simulate)
				shift; simulate="${1:-}"; warnEmptyValue '-s' "$simulate"; shift ;;
			-v | --verbose)
				shift; verbose="${1:-}"; warnEmptyValue '-v' "$verbose"; shift ;;
			-*)
				error "Unknown option: '$1'"; usage; exit 1 ;;
		esac
	done
	}


checkCliParameters() {
	local errorFound=0
	[ -d "$gitRepoDir" ] || { error "Directory '$gitRepoDir' not found"; errorFound=1; }

	[ "$verbose" -ne 0 -a "$verbose" -ne 1 ] && { error "'verbose' must be either 0 or 1"; errorFound=1; }

	[ "$simulate" -ne 0 -a "$simulate" -ne 1 ] && { error "'simulate' must be either 0 or 1"; errorFound=1; }

	[ "$errorFound" -eq 1 ] && { usage; exit 1; }
	}


getAbsoluteGitRepoDir() {
	absolutePathToGitRepoRootDir=$(readlink -f "$gitRepoDir")

	# check this is a Git repo dir
	[ -d "$absolutePathToGitRepoRootDir/.git" ] || { error "No '$absolutePathToGitRepoRootDir/.git' directory found, '$absolutePathToGitRepoRootDir' is not the root directory of a Git repository"; exit 1; }

	workDir="$absolutePathToGitRepoRootDir"
	}


confirmContinueWithoutSimulating() {
	[ "$simulate" -eq 0 ] && {
		cat <<-EOCONFIRM

		This script is NOT running in simulation mode and WILL CHANGE data.

		Press :
		- CTRL-c to abort
		- ENTER  to continue
		EOCONFIRM
		read;
		}
	}


checkGitFilterRepoIsAvailable() {
	git filter-repo --version &>/dev/null || {
		cat <<-EOCHECK
		Looks like 'git filter-repo' is not installed.

		For details, please visit https://github.com/newren/git-filter-repo#how-do-i-install-it

		For the impatients, this does the job:
		    sudo apt install git-filter-repo

		EOCHECK
		exit 1
		}
	}


initializeVariables() {
	output='/dev/null'
	[ "$verbose" == '1' ] && output='/dev/stdout'

	# if simulate==1, work on a clone of the repo
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
	cat <<-EOWORKING

	Working on '$fileToRemoveFromGitHistory' :
	- occurrences : $nbOccurrences
	- current size : $currentFileSize
	EOWORKING
	}


makeBackupOfFileToRemove() {
	local fileToRemove=$1
	[ "$keepLatestVersion" -eq 1 ] && cp "$fileToRemove" "$tmpBaseDir"
	}


restoreFileToRemove() {
	local fileToRemove=$1

	# Git dislikes empty directories and may have deleted the one storing "$fileToRemove"
	# if this file was the only one in there
	mkdir -p "$(dirname ${fileToRemove})"

	[ "$keepLatestVersion" -eq 1 ] && mv "$tmpBaseDir/$(basename "$fileToRemove")" "$fileToRemove"
	git add "$fileToRemove"
	git commit -m "new 'initial' version after wiping file history"
	}


removeFileFromHistory() {
	local fileToRemove=$1
	git filter-repo --invert-paths --path "$fileToRemove" 1>"$output" || { echo 'Houston, we have a problem.'; exit 1; }
	}


checkFileWasRemoved() {
	local fileToRemove=$1
	nbEntriesInLog=$(git log --oneline -- "$fileToRemove" | wc -l)
	[ "$nbEntriesInLog" -gt 0 -o -f "$fileToRemove" ] && { echo "Looks like '$fileToRemove' is still there."; exit 1; }
	}


removeUnitPrefixLetter() {
	local numberWithUnitPrefixLetter=$1
	echo ${numberWithUnitPrefixLetter%[kmgtKMGT]}
	}


displayRepoSize() {
	local message=$1
	local sizeBefore=$2
	local sizeAfter=$3

	sizeBefore_noUnit=$(removeUnitPrefixLetter "$sizeBefore")
	sizeAfter_noUnit=$(removeUnitPrefixLetter "$sizeAfter")

	cat <<-EOSIZE
	SIZE BEFORE ($message) :	$sizeBefore
	SIZE AFTER  ($message) :	$sizeAfter
	DIFFERENCE : $((sizeBefore_noUnit-sizeAfter_noUnit))
	EOSIZE
	}


doFinalCleaning() {
	# the '--aggressive' directive
	#	- makes the script WAY slower
	#	- does not save that much space :-/
	# TODO: correct way to do this : https://stackoverflow.com/questions/5613345/how-to-shrink-the-git-folder/8483112#8483112
	git gc --prune=now
	}


getFieldFromDataLine() {
	local fieldNb="$1"
	local dataLine="$2"
	echo "$dataLine" | cut -d ';' -f "$fieldNb"
	}


getCleanDataLineValues() {
	local dataLine="$1"
	fileToRemoveFromGitHistory=$(getFieldFromDataLine 1 "$dataLine")
	keepLatestVersion=$(getFieldFromDataLine 2 "$dataLine")

	[ -f "$fileToRemoveFromGitHistory" ] || { info "File '$fileToRemoveFromGitHistory' not found, skipping"; continue=1; }
	[ "$keepLatestVersion" != '0' -a "$keepLatestVersion" != '1' ] && { error "'keepLatestVersion' must be either 0 or 1 for file '$fileToRemoveFromGitHistory'"; exit 1; }
	}


main() {
	getCliParameters "$@"
	checkCliParameters
	getAbsoluteGitRepoDir
	confirmContinueWithoutSimulating
	checkGitFilterRepoIsAvailable
	initializeVariables
	cd "$workDir"
	sizeBeforeRemovingAllListedFiles=$(getDirSize '.')
	while read dataLine; do

		[[ "$dataLine" =~ ^(#|$) ]] && continue
		continue=0
		getCleanDataLineValues "$dataLine"
		[ "$continue" -eq 1 ] && continue

		sizeBeforeRemovingThisFile=$(getDirSize '.')
		countOccurrencesOfFileToRemove "$fileToRemoveFromGitHistory"
		makeBackupOfFileToRemove "$fileToRemoveFromGitHistory"
		removeFileFromHistory "$fileToRemoveFromGitHistory"
		checkFileWasRemoved "$fileToRemoveFromGitHistory"
		restoreFileToRemove "$fileToRemoveFromGitHistory"
		sizeAfterRemovingThisFile=$(getDirSize '.')
		displayRepoSize 'removed 1 file' "$sizeBeforeRemovingThisFile" "$sizeAfterRemovingThisFile"
	done < "$dataFile"

	doFinalCleaning
	sizeAfterRemovingAllListedFiles=$(getDirSize '.')
	displayRepoSize 'removed all listed files' "$sizeBeforeRemovingAllListedFiles" "$sizeAfterRemovingAllListedFiles"
	}


main "$@"
