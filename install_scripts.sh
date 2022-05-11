#!/usr/bin/env bash

SCRIPTS=$(realpath $(dirname "$0"))/scripts

# does a "scripts" folder exist in this directory?
if [ -d "$SCRIPTS" ] ; then

   # the winner by default is
   WINNER="$HOME/.local/bin"

   # does the winner exist?
   if [ ! -d "$WINNER" ] ; then

      # check the search path
      for CANDIDATE in ${PATH//:/ }; do
         if [[ $CANDIDATE == $HOME* ]] ; then
            WINNER="$CANDIDATE"
            break
         fi
      done

   fi

   # make sure the winner exists
   mkdir -p "$WINNER"

   # copy executables into place
   cp -av "$SCRIPTS"/* "$WINNER"

else

   echo "Skipped: $SCRIPTS not found in $PWD"

fi

# check if shyaml is installed
if [ -z "$(which shyaml)" ] ; then

   echo ""
   echo "=========================================================================="
   echo "\"iotstack_backup\" and \"iotstack_restore\" depend on \"shyaml\" which does not"
   echo "seem to be installed on your system. Please run the following command:"
   echo ""
   echo "   sudo pip3 install -U shyaml"
   echo ""
   echo "You can omit the \"sudo\" if you only want \"shyaml\" to be installed for the"
   echo "local user instead of being made available system-wide."
   echo "=========================================================================="

fi
