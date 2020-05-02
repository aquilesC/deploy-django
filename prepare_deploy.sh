#!/bin/bash
#
# Usage:
#	$ create_django_project_run_env <appname>

source ./common_funcs.sh

check_root

# conventional values that we'll use throughout the script
APPNAME=$1

# check appname was supplied as argument
if [ "$APPNAME" == "" ]; then
	echo "Usage:"
	echo "  $ prepare_deploy.sh <project>"
	echo
	exit 1
fi

GROUPNAME=webapps
# app folder name under /webapps/<appname>
APPFOLDER=$1
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

# ###################################################################
# Create the app folder
# ###################################################################
echo "Creating app folder '$APPFOLDERPATH'..."
mkdir -p /$GROUPNAME/$APPFOLDER || error_exit "Could not create app folder"

# test the group 'webapps' exists, and if it doesn't create it
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    echo "Creating group '$GROUPNAME' for automation accounts..."
    groupadd $GROUPNAME || error_exit "Could not create group 'webapps'"
fi

# create the app user account, same name as the appname
grep "$APPNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    echo "Creating automation user account '$APPNAME'..."
    useradd --gid $GROUPNAME --shell /bin/bash --home $APPFOLDERPATH $APPNAME || error_exit "Could not create automation user account '$APPNAME'"
fi

# change ownership of the app folder to the newly created user account
echo "Setting ownership of $APPFOLDERPATH and its descendents to $APPNAME:$GROUPNAME..."
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH || error_exit "Error setting ownership"
# give group execution rights in the folder;
# TODO: is this necessary? why?
chmod g+x $APPFOLDERPATH || error_exit "Error setting group execute flag"

# install python virtualenv in the APPFOLDER
echo "Creating environment setup for django app..."
su -l $APPNAME << 'EOF'
pwd
echo "Setting up python virtualenv..."
virtualenv -p python3 venv || error_exit "Error installing Python 3 virtual environment to app folder"

EOF

# ###################################################################
# In the new app specific virtual environment:
# 	1. Upgrade pip
#	  2. Create following folders:-
#		  static -- Django static files (to be collected here)
#		  media  -- Django media files
#		  logs   -- nginx, gunicorn & supervisord logs
#		  nginx  -- nginx configuration for this domain
# ###################################################################
su -l $APPNAME << 'EOF'
source venv/bin/activate
# upgrade pip
pip install --upgrade pip || error_exist "Error upgrading pip to the latest version"
EOF

echo "Before fnishing, let's copy the SSH keys to be able to send files to the app using SSH"
mkdir $APPFOLDERPATH/.ssh
cp $HOME/.ssh/authorized_keys /$APPFOLDERPATH/.ssh/
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH/.ssh
chmod 700 $APPFOLDERPATH/.ssh
chmod 600 $APPFOLDERPATH/.ssh/authorized_keys

echo "Done!"
echo "Now it is time to copy the project files to $APPFOLDERPATH"
echo "When done, continue with deploy_django.sh"