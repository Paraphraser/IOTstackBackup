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
