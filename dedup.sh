#!/bin/bash

####################################################################################
#
# FILE:         dedup.sh
#
# USAGE:        dedup.sh [OPTIONS] starting_directory
#
# DESCRIPTION:  Script for deduplicate of files and replace them with hardlinks.
#               The default starting directory is the current directory.
#               Don’t work across filesystems.
#
# OPTIONS:      See function ’usage’ below.
#
# REQUIREMENTS: /usr/bin/cmp
#               /usr/bin/md5sum
#
# NOTES:        See README.md
#
# AUTHOR:       Andreas Klamke
#
# VERSION:      1.0.1
#
# CREATED:      12.12.2015
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
            \rUsage: $script_name [OPTION]... DIRECTORY
            \rDeduplicate files and replace duplicates with hardlinks.

            \rMandatory arguments to long options are mandatory for short options too.
            \r  -b, --backup        hard linked files will be backuped like file.~1~
            \r  -d, --dry-run       runs in dry-run mode
            \r  -i, --interactive   prompt whether to remove duplicate files before
            \r                      hard links will be created
            \r  -r, --recursive     recursive through subdirectories
            \r  -h, --help          display this help and exit
            \r  -v, --verbose       more details in output

            \rIf DIRECTORY is '-' or missing, current directory is used.
            \rExit status is 0 if no error occures, otherwise exit status is 1.

            \rReport bugs on: https://github.com/FlatKey/dedup
            "

    exit 0

}

function validate_directory {

    # validates the given directory
    if [[ ! -d "$1" ]]
    then
        echo -e "\nERROR - $1 is not a existing directory!\n" 1>&2
        exit 1
    fi

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

    # print title in verbose mode only
    if [[ $verbose -eq 1 ]]; then echo -e "\nRetrieve file checksums:\n========================\n"; fi

    # find all files recursivly in given directory and associate them in an array with their md5sum
    if [[ $recursive -eq 1 ]]
    then
        findcommand="find $1 -type f -size +0c -print0"
    else
        findcommand="find $1 -maxdepth 1 -type f -size +0c -print0"
    fi
    while IFS= read -r -d '' file
    do
        filestring=$(printf '%q\n' "$file")
        checksumarray["'"$filestring"'"]=$( sh -c "md5sum $filestring|cut -d' ' -f1")
    done < <($findcommand 2>/dev/null)

    # print md5sum - file associations in verbose mode only
    if [[ $verbose -eq 1 ]]
    then 
        for checksum in "${!checksumarray[@]}"
        do
            echo "${checksumarray[$checksum]} - $checksum"
        done
    fi

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

    # the main deduplication logic of this script
    echo -e "\nDeduplicate files:\n==================\n"

    filecount="${#checksumarray[@]}"
    keyarray=("${!checksumarray[@]}")
    hardlinkcount=0
    freedbytes=0
    while [[ $filecount -gt 1 ]]
    do
        actualfile=$(echo "${keyarray[$filecount-1]}"| sed "s/^.//" | sed "s/.$//")
        actualchecksum="${checksumarray[${keyarray[$filecount-1]}]}"

        if [[ $actualchecksum != "###" ]]
        then
            for (( i=$filecount-1; $i > 0; i-=1 ))
            do
                comparefile=$(echo "${keyarray[$i-1]}"| sed "s/^'*//g" | sed "s/'*$//g")
                comparechecksum="${checksumarray[${keyarray[$i-1]}]}"

                if [[ "$actualchecksum" == "$comparechecksum" ]]
                then
                    if [[ $(stat -c %i "$actualfile") == $(stat -c %i "$comparefile") ]]
                    then
                        if [[ $verbose -eq 1 ]]; then echo -e "$actualfile & $comparefile -> already hardlinked."; fi
                    elif [[ $(stat -c %m "$actualfile") != $(stat -c %m "$comparefile") ]]
                    then
                        if [[ $verbose -eq 1 ]]; then echo -e "$actualfile & $comparefile -> equal md5 checksum, but not located on the same filesystem."; fi
                    else
                        echo -e "$actualfile & $comparefile -> equal md5 checksum, they will be compared byte-by-byte:"
                        cmpmessage=$(cmp "$actualfile" "$comparefile" 2>&1)
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
                                
                                if [[ $dry_run -eq 0 ]]; then $($linkcommand "$actualfile" "$comparefile"); fi
                                let hardlinkcount+=1
                                let freedbytes="$(( $freedbytes + $(stat -c %s "$comparefile") ))"
                            echo -e "done\n"
                        else
                            echo -e "$cmpmessage"
                            echo -e "Files not equal, nothing to do."
                        fi
                    fi
                    checksumarray[${keyarray[$i-1]}]="###"
                fi
            done
        fi

        let filecount-=1
        echo -ne "$(( ${#checksumarray[@]} - $filecount + 1 )) files checked.\r"
    done
    echo -e "\n"

    # print deduplicate summary in verbose mode only
    if [[ $verbose -eq 1 ]]; then echo -e "$hardlinkcount linkable duplicates found."; fi

}

function show_summary {

    # print summary of script activities
    echo -e "\nSummary:\n========\n"
    echo -e "${#checksumarray[@]} files found and checked."
    echo -e "$hardlinkcount linkable duplicates found."
    echo -e "$freedbytes bytes of disk space freed.\n"

}

# main

if [[ $# == 0 ]]
then
    echo -e "$script_name: missing operand after '$script_name'"
    echo -e "$script_name: Try '$script_name --help' for more information."
    exit 1
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
            validate_directory $1
            show_script_header
            show_script_options
            build_file_checksum_array $1
            process_deduplication
            show_summary
            ;;
    esac
shift
done

exit 0
