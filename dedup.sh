#!/bin/bash

####################################################################################
#
# FILE:         dedup.sh
#
# USAGE:        dedup.sh.sh [-d] [-r] [-v] starting_directory
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
# NOTES:        ---
#
# AUTHOR:       Andreas Klamke
#
# VERSION:      0.1
#
# CREATED:      13.11.2015
#
####################################################################################

# global defined variables

script_name=$(basename $0)
dry_run=0
recursive=0
verbose=0

# functions

function usage {
    echo -e "
            \rUsage: $script_name [OPTION]... DIRECTORY
            \rDeduplicate files and replace duplicates with hardlinks.

            \rMandatory arguments to long options are mandatory for short options too.
            \r  -d, --dry-run       runs in dry-run mode
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
    if [[ ! -d "$1" ]]
    then
        echo -e "\nERROR - $1 is not a existing directory!\n" 1>&2
        exit 1
    fi
}

function show_script_header {
    echo -e "\n[ Deduplication startet... ]\n"

    echo -e "Options:\n========"
    if [[ $dry_run -eq 1 ]]
    then
        echo -e "- dry_run on"
    fi
    if [[ $recursive -eq 1 ]]
    then
        echo -e "- recursive on"
    fi
    if [[ $verbose -eq 1 ]]
    then
        echo -e "- verbose on"
    fi
}

function build_file_checksum_array {
    echo -e "\nRetrieve file checksums:\n========================"
}

function process_deduplication {
    echo -e "\nDeduplicate files:\n=================="
}

function show_summary {
    echo -e "\nSummary:\n========"
}

# main

if [[ $# == 0 ]]
then
    echo -e "$script_name: missing operand after '$script_name'"
    echo -e "$script_name: Try '$script_name --help' for more information."
    exit 1
fi

while [ $# -gt 0 ]
do
    case ${1,,} in
        -h|--help) 
            usage
            exit 0
            ;;
        -d|--dry-run)
            dry_run=1
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
            build_file_checksum_array
            process_deduplication
            show_summary
            ;;
    esac
shift
done

exit 0
