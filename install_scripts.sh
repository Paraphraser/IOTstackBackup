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

# check apt-installable dependencies
for D in curl jq wget ; do
   if [ -z "$(which "$D")" ] ; then
      echo ""
      echo "=========================================================================="
      echo "IOTstackBackup depends on \"$D\" which does not seem to be installed on your"
      echo "system. Please run the following command:"
      echo ""
      echo "   sudo apt install $D"
      echo ""
      echo "=========================================================================="
   fi
done

# check if mosquitto_pub is available
if [ -z "$(which mosquitto_pub)" ] ; then

   echo ""
   echo "=========================================================================="
   echo "IOTstackBackup depends on \"mosquitto_pub\" which does not seem to be installed"
   echo "on your system. Please run the following command:"
   echo ""
   echo "   sudo apt install mosquitto-clients"
   echo ""
   echo "=========================================================================="

fi

# check if shyaml is installed
if [ -z "$(which shyaml)" ] ; then

   echo ""
   echo "=========================================================================="
   echo "IOTstackBackup depends on \"shyaml\" which does not seem to be installed on your"
   echo "system. Please run the following command:"
   echo ""
   echo "   sudo pip3 install -U shyaml"
   echo ""
   echo "You can omit the \"sudo\" if you only want \"shyaml\" to be installed for the"
   echo "local user instead of being made available system-wide."
   echo "=========================================================================="

fi

# check for rclone
if [ -z "$(which rclone)" ] ; then

   echo ""
   echo "=========================================================================="
   echo "If you intend to use RCLONE with IOTstackBackup, please note that it is not"
   echo "installed on your system. Please run the following command:"
   echo ""
   echo "   https://rclone.org/install.sh | sudo bash"
   echo ""
   echo "=========================================================================="

fi
