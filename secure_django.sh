#!/bin/bash
#
# Usage:
#	$ deploy_django.sh <appname> <domainname> assumes django APP is in /webapps/<appname>/<appname>

source ./common_funcs.sh

check_root

# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2

echo "Adding Certbot repository and installing certbot"
add-apt-repository ppa:certbot/certbot
apt-get update
apt-get install python-certbot-nginx

echo "Setting UFW rules to allow ssl"
ufw allow 'Nginx Full'
ufw delete allow 'Nginx HTTP'
certbot --nginx -d $DOMAINNAME