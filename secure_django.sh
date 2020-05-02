#!/bin/bash
#
# Usage:
#	$ secure_django.sh <domainname>

source ./common_funcs.sh

check_root

DOMAINNAME=$1

# check appname was supplied as argument
if [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ secure_django <domain>"
	echo
	exit 1
fi

echo "Adding Certbot repository and installing certbot"
add-apt-repository ppa:certbot/certbot
apt-get update
apt-get install python-certbot-nginx

echo "Setting UFW rules to allow ssl"
ufw allow 'Nginx Full'
ufw delete allow 'Nginx HTTP'
certbot --nginx -d $DOMAINNAME