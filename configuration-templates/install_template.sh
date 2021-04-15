#!/usr/bin/env bash

# should not run as root
[ "$EUID" -eq 0 ] && echo "This script should NOT be run using sudo" && exit -1

# exactly one argument
if [ "$#" -ne 1 ]; then
   echo "Usage: $(basename "$0") template"
   exit -1
fi

TEMPLATES_DIR=$(realpath $(dirname "$0"))
TEMPLATE=${1^^}
CONFIG_DIR="$HOME/.config/iotstack_backup"
CONFIG_YML="config.yml"

# ensure the configuration directory exists
mkdir -p "$CONFIG_DIR"
TILDED_DIR=$(cd "$CONFIG_DIR" && dirs +0)

# does a configuration file exist already?
if [ ! -e "$CONFIG_DIR/$CONFIG_YML" ] ; then

   # no! does the requested template exit?
   if [ -e "$TEMPLATES_DIR/$TEMPLATE/$CONFIG_YML" ] ; then

      # yes! copy the template file into place
      cp -a "$TEMPLATES_DIR/$TEMPLATE/$CONFIG_YML" "$CONFIG_DIR/$CONFIG_YML"
      echo "$TEMPLATE template copied to $TILDED_DIR/$CONFIG_YML"

    else

      echo "Skipped: ./$TEMPLATE does not exist or does not contain $CONFIG_YML"

    fi

else

   echo "Skipped: a configuration file already exists. This is a safety"
   echo "         feature to avoid accidentally overwriting a working"
   echo "         configuration. If you really want to install a new"
   echo "         template:"
   echo "         1. rm $TILDED_DIR/$CONFIG_YML"
   echo "         2. re-run this command"

fi
