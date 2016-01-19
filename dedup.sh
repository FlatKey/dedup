#!/bin/bash

####################################################################################
#
# FILE:         dedup.sh
#
# USAGE:        dedup.sh [OPTION]... [DIRECTORY]...
#
# DESCRIPTION:  Script for deduplicate of files and replace them with hardlinks.
#               The default directory is the current directory.
#               Don’t work across filesystems.
#
# OPTIONS:      See function ’usage’ below.
#
# REQUIREMENTS: bc
#               cmp
#               date
#               md5sum
#
# NOTES:        See README.md
#
# AUTHOR:       Andreas Klamke
#
# VERSION:      2.0.2
#
# CREATED:      12.12.2015
#
# UPDATED:      18.01.2016
#
####################################################################################

# global defined variables with default values

script_name=$(basename $0)
backup=0
dry_run=0
interactive=0
recursive=0
verbose=0

declare -A checksumarray

# functions

function usage {

    # print usage manual
    echo -e "
            \rUsage: $script_name [OPTION]... [DIRECTORY]...
            \rDeduplicate files and replace duplicates with hardlinks.

            \rMandatory arguments to long options are mandatory for short options too.
            \r  -b, --backup        hard linked files will be backuped like file.~1~
            \r  -d, --dry-run       runs in dry-run mode
            \r  -i, --interactive   prompt whether to remove duplicate files before
            \r                      hard links will be created
            \r  -r, --recursive     recursive through subdirectories
            \r  -h, --help          display this help and exit
            \r  -v, --verbose       more details in output

            \rIf DIRECTORY is missing, current directory is used.
            \rExit status is 0 if no error occures, otherwise exit status is 1.

            \rReport bugs on: https://github.com/FlatKey/dedup
            "

    exit 0

}

function check_requirements {

    # check if script requirements exist
    command -v bc &>/dev/null
    if [[ ! $? -eq 0 ]]
    then
        echo -e "\nERROR - The required program bc does not exist!\n"
        exit 1
    fi
    command -v cmp &>/dev/null
    if [[ ! $? -eq 0 ]]
    then
        echo -e "\nERROR - The required program cmp does not exist!\n"
        exit 1
    fi
    command -v date &>/dev/null
    if [[ ! $? -eq 0 ]]
    then
        echo -e "\nERROR - The required program date does not exist!\n"
        exit 1
    fi
    command -v md5sum &>/dev/null
    if [[ ! $? -eq 0 ]]
    then
        echo -e "\nERROR - The required program md5sum does not exist!\n"
        exit 1
    fi

}

function validate_directory {

    # validates the given directory arguments
    for directory in "$@"
    do
        if [[ ! -d "$directory" ]]
        then
            echo -e "\nERROR - $directory is not a existing directory!\n" 1>&2
            exit 1
        fi
    done

}

function show_script_header {

    # print script header
    echo -e "\n| dedup.sh                 |"
    echo -e "\r| @2015 by Andreas Klamke  |"

}

function show_script_options {

    # print script options in verbose mode only
    if [[ $verbose -eq 1 ]]
    then 
        echo -e "\nOptions:\n========\n"
        if [[ $backup -eq 1 ]]
        then
            echo -e "- backup on"
        fi
        if [[ $dry_run -eq 1 ]]
        then
            echo -e "- dry_run on"
        fi
        if [[ $interactive -eq 1 ]]
        then
            echo -e "- interactive on"
        fi
        if [[ $recursive -eq 1 ]]
        then
            echo -e "- recursive on"
        fi
        echo -e "- verbose on"
    fi

}

function build_file_checksum_array {

    # take time for process duration measurement
    time_checksum_build_started=$(date --date "now" "+%s")

    # print title in verbose mode only
    if [[ $verbose -eq 1 ]]; then echo -e "\nRetrieve file checksums:\n========================\n"; else echo -e "\nPreparing deduplication process...\n"; fi

    # find all files recursivly in given directory arguments and associate them in an array with their md5sum
    if [[ $recursive -eq 1 ]]
    then
        findcommand="find '$@' -type f -size +0c -print0"
    else
        findcommand="find '$@' -maxdepth 1 -type f -size +0c -print0"
    fi
    while IFS= read -r -d '' file
    do
        filestring=$(printf '%q\n' "$file")

        # check if checksum can be retrieved, otherwise ignore file
        checksum=$(bash -c "md5sum $filestring" 2>&1)
        if [[ "$?" -eq 0 ]]
        then
            checksum=$(bash -c "echo $checksum|cut -d' ' -f1")
            checksumarray["'"$filestring"'"]="$checksum"

            # print md5sum - file associations in verbose mode only
            if [[ $verbose -eq 1 ]]
            then
                echo "${checksumarray["'"$filestring"'"]} - '$filestring'"
            fi
        fi
    done < <(bash -c "$findcommand 2>/dev/null")

    # abort script if less than 2 files were found
    if [[ ${#checksumarray[@]} -lt 2 ]]
    then
        echo -e "ERROR - found less than 2 files!\n"
        exit 1
    fi

    # print indexed summary in verbose mode only
    if [[ $verbose -eq 1 ]]; then echo -e "\n${#checksumarray[@]} files indexed."; fi

}

function process_deduplication {

    # take time for process duration measurement
    time_deduplication_started=$(date --date "now" "+%s")

    # the main deduplication logic of this script
    echo -e "\nDeduplicate files:\n==================\n"

    # sort array indexes by checksums to avoid the exponential problem with one file to all file comparision
    IFS=$'\n'
    keyarray=($(
        for key in "${!checksumarray[@]}"
        do
            printf '%s:%s\n' "$key" "${checksumarray[$key]}"
        done | sort -t : -k 2 | sed 's/:.*//'))
    unset IFS

    filecount="${#checksumarray[@]}"
    probablyhardlinkablecount=0
    hardlinkablecount=0
    hardlinkcount=0
    freeablebytes=0
    freedbytes=0
    while [[ $filecount -gt 1 ]]
    do
        # needed to compare the actuale file only with the next file as consequence of the sorted indexes
        actualfile=$(echo "${keyarray[$filecount-1]}"| sed "s/^.//" | sed "s/.$//")
        actualchecksum="${checksumarray[${keyarray[$filecount-1]}]}"
        comparefile=$(echo "${keyarray[$filecount-2]}"| sed "s/^.//" | sed "s/.$//")
        comparechecksum="${checksumarray[${keyarray[$filecount-2]}]}"

        if [[ "$actualchecksum" == "$comparechecksum" ]]
        then
            if [[ $(bash -c "stat -c %i $actualfile") == $(bash -c "stat -c %i $comparefile") ]]
            then
                if [[ $verbose -eq 1 ]]; then echo -e "$actualfile & $comparefile -> already hardlinked."; fi
            elif [[ $(bash -c "stat -c %m $actualfile") != $(bash -c "stat -c %m $comparefile") ]]
            then
                if [[ $verbose -eq 1 ]]; then echo -e "$actualfile & $comparefile -> equal md5 checksum, but not located on the same filesystem."; fi
                probablyhardlinkablecount+=1
            else
                echo -e "$actualfile & $comparefile -> equal md5 checksum, they will be compared byte-by-byte:"
                cmpmessage=$(bash -c "cmp $actualfile $comparefile 2>&1")
                if [[ $? -eq 0 ]]
                then
                    echo -n "Files match, they will be hard linked... "
                    linkcommand="ln"

                    if [[ $backup -eq 1 ]]
                    then
                        linkcommand="$linkcommand --backup=numbered"
                    fi

                    if [[ $interactive -eq 1 ]]
                    then
                        linkcommand="$linkcommand -i"
                    else
                        linkcommand="$linkcommand -f"
                    fi

                    if [[ $dry_run -eq 0 ]]; then $(bash -c "$linkcommand $actualfile $comparefile"); linkerror=$?; fi

                    if [[ $linkerror -eq 0 ]]
                    then
                        let freedbytes="$(( $freedbytes + $(bash -c "stat -c %s $comparefile") ))"
                        let hardlinkcount+=1
                        echo -e "done\n"
                    else
                        echo -e "failed\n"
                    fi

                    let freeablebytes="$(( $freeablebytes + $(bash -c "stat -c %s $comparefile") ))"
                    let hardlinkablecount+=1
                else
                    echo -e "$cmpmessage"
                    echo -e "Files not equal, nothing to do."
                fi
            fi
        fi

        let filecount-=1
        echo -ne "$(( ${#checksumarray[@]} - $filecount + 1 )) files checked.\r"
    done
    echo -e "\n"

    # print deduplicate summary in verbose mode only
    if [[ $verbose -eq 1 ]]; then echo -e "$hardlinkcount linkable duplicates found."; fi

}

function show_summary {

    # take time for process duration measurement
    time_process_finished=$(date --date "now" "+%s")

    # calculate needed time for processing
    time_checksum_build=$(($time_deduplication_started - $time_checksum_build_started))
    time_deduplication=$(($time_process_finished - $time_deduplication_started))

    # calculate scale unit for freeable disk space
    if [[ $freeablebytes -ge 1073741824 ]]
    then
        freeablebytes=$(bc <<< "scale=2; $freeablebytes / 1073741824" )
        freeablescaleunit="GiB"
    elif [[ $freeablebytes -ge 1048576 ]]
    then
        freeablebytes=$(bc <<< "scale=2; $freeablebytes / 1048576" )
        freeablescaleunit="MiB"
    elif [[ $freeablebytes -ge 1024 ]]
    then
        freeablebytes=$(bc <<< "sclae=2; $freeablebytes / 1024" )
        freeablescaleunit="KiB"
    else
        freeablescaleunit="bytes"
    fi

    # calculate scale unit for freed disk space
    if [[ $freedbytes -ge 1073741824 ]]
    then
        freedbytes=$(bc <<< "scale=2; $freedbytes / 1073741824" )
        freedscaleunit="GiB"
    elif [[ $freedbytes -ge 1048576 ]]
    then
        freedbytes=$(bc <<< "scale=2; $freedbytes / 1048576" )
        freedscaleunit="MiB"
    elif [[ $freedbytes -ge 1024 ]]
    then
        freedbytes=$(bc <<< "sclae=2; $freedbytes / 1024" )
        freedscaleunit="KiB"
    else
        freedscaleunit="bytes"
    fi

    # print summary of script activities
    echo -e "\nSummary:\n========\n"
    echo -e "$time_checksum_build seconds needed to retrieve all file checksums."
    echo -e "$time_deduplication seconds needed for the deduplication process."
    echo -e "${#checksumarray[@]} files found and checked."
    echo -e "$probablyhardlinkablecount probably duplicates found on different filesystems."
    echo -e "$hardlinkablecount duplicates found."
    echo -en "$hardlinkcount files deduplicated."; if [[ $interactive -eq 1 ]]; then echo -e " (if all interactive decisions were 'yes'."; else echo -e ""; fi
    echo -e "$freeablebytes $freeablescaleunit of disk space probably freeable."
    echo -en "$freedbytes $freedscaleunit of disk space freed."; if [[ $interactive -eq 1 ]]; then echo -e " (if all interactive decisions were 'yes'.\n"; else echo -e "\n"; fi

}

# main

if [[ $# == 0 ]]
then
    echo -e "$script_name: missing operand after '$script_name'"
    echo -e "$script_name: Try '$script_name --help' for more information."
    exit 1
fi

# test if a directory argument exist
for argument in "$@"
do
    if [[ ! $argument == "-"* ]]
    then
        directory_argument_exists=1
    fi
done

# set current directory if no directory argument exist
if [[ ! $directory_argument_exists -eq 1 ]]
then
    set -- "$@" "$(pwd)"
fi

while [[ $# -gt 0 ]]
do
    case ${1,,} in
        -h|--help) 
            usage
            exit 0
            ;;
        -b|--backup)
            backup=1
            ;;
        -d|--dry-run)
            dry_run=1
            ;;
        -i|--interactive)
            interactive=1
            ;;
        -r|--recursive)
            recursive=1
            ;;
        -v|--verbose)
            verbose=1
            ;;
        -*|--*)
            echo "\nERROR - $1 option does not exist!\n" 1>&2
            exit 1
            ;;
        *)
            if [[ $# -gt 1 ]]
            then
                directories="$@"
                shift $#
            else
                directories="$1"
            fi

            check_requirements
            validate_directory "$directories"
            show_script_header
            show_script_options
            build_file_checksum_array "$directories"
            process_deduplication
            show_summary
            ;;
    esac
shift
done

exit 0
