#!/bin/bash

set -o errexit   # abort on nonzero exitstatus. Same as 'set -e'
set -o nounset   # abort on unbound variable. Same as 'set -u'
set -o pipefail  # don't hide errors within pipes

# Uncomment below line when debugging to get trace output
# set -o xtrace    # print trace

usage() {
    echo "usage: $(basename "$0")"
}

# to add a flag that is a toggle just add a letter, e.g 'a'
# to add a flag with an argument just add a letter followed by a colon, e.g. 'a:'
while getopts ":hl" opt; do
  case ${opt} in
    h )
      usage
      exit 0
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      usage
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

