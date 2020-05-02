#!/bin/bash
#
# Usage:
#	$ deploy_django.sh <appname> <domainname> assumes django APP is in /webapps/<appname>/<appname>

source ./common_funcs.sh

check_root

# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2

# check appname was supplied as argument
if [ "$APPNAME" == "" ] || [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ create_django_project_run_env <project> <domain>"
	echo
	exit 1
fi


GROUPNAME=webapps
# app folder name under /webapps/<appname>
APPFOLDER=$1
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER
DJANGOFOLDER=/$GROUPNAME/$APPFOLDER/$APPFOLDER

cd $APPFOLDERPATH

echo "Activating the environment and installing dependencies"
su -l $APPNAME << EOF
source venv/bin/activate
pip install -r $DJANGOFOLDER/requirements/production.txt
echo "Creating static file folders..."
mkdir logs nginx run static media || error_exit "Error creating static folders"
# Create the UNIX socket file for WSGI interface
echo "Creating WSGI interface UNIX socket file..."
python -c "import socket as s; sock = s.socket(s.AF_UNIX); sock.bind('./run/gunicorn.sock')"
EOF

# ###################################################################
# Let's get the important information from the .env files
# ###################################################################
echo "Securing the env files by making them read-only"
chown -R $APPNAME:$GROUPNAME $DJANGOFOLDER/.envs
chmod -R 700 $DJANGOFOLDER/.envs/.production/

echo "Creating the database"
DBPASSWORD=$(read_var POSTGRES_PASSWORD $DJANGOFOLDER/.envs/.production/.postgres)
DBUSER=$(read_var POSTGRES_USER $DJANGOFOLDER/.envs/.production/.postgres)
DATABASE=$(read_var POSTGRES_DB $DJANGOFOLDER/.envs/.production/.postgres)

# ###################################################################
# Create the PostgreSQL database and associated role for the app
# Database and role name would be the same as the <appname> argument
# ###################################################################
echo "Creating PostgreSQL role '$DBUSER'..."
su postgres -c "createuser -S -D -R -w $DBUSER"
echo "Changing password of database role..."
su postgres -c "psql -c \"ALTER USER $DBUSER WITH PASSWORD '$DBPASSWORD';\""
echo "Creating PostgreSQL database '$DATABASE'..."
su postgres -c "createdb --owner '$DBUSER' '$DATABASE'"


# ###################################################################
# Create the script that will init the virtual environment. This
# script will be called from the gunicorn start script created next.
# ###################################################################
echo "Creating virtual environment setup script..."
cat > /tmp/prepare_env.sh << EOF
DJANGODIR=$DJANGOFOLDER          # Django project directory

export DJANGO_SETTINGS_MODULE=config.settings.production # settings file for the app
export PYTHONPATH=\$DJANGODIR:\$PYTHONPATH
cd $APPFOLDERPATH
source venv/bin/activate
EOF
mv /tmp/prepare_env.sh $APPFOLDERPATH
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/prepare_env.sh

# ###################################################################
# Create gunicorn start script which will be spawned and managed
# using supervisord.
# ###################################################################
echo "Creating gunicorn startup script..."
cat > /tmp/gunicorn_start.sh << EOF
#!/bin/bash
# Makes the following assumptions:
#
#  1. All applications are located in a subfolder within /webapps
#  2. Each app gets a dedicated subfolder <appname> under /webapps. This will
#     be referred to as the app folder.
#  3. The group account 'webapps' exists and each app is to be executed
#     under the user account <appname>.
#  4. The app folder and all its recursive contents are owned by
#     <appname>:webapps.
#  5. The django app is stored under /webapps/<appname>/<appname> folder.
#

cd $APPFOLDERPATH
source ./prepare_env.sh

SOCKFILE=$APPFOLDERPATH/run/gunicorn.sock  # we will communicte using this unix socket
USER=$APPNAME                                        # the user to run as
GROUP=$GROUPNAME                                     # the group to run as
NUM_WORKERS=3                                     # how many worker processes should Gunicorn spawn
DJANGO_WSGI_MODULE=$APPNAME.wsgi                     # WSGI module name

echo "Starting $APPNAME as \`whoami\`"

# Create the run directory if it doesn't exist
RUNDIR=\$(dirname \$SOCKFILE)
test -d \$RUNDIR || mkdir -p \$RUNDIR

# Start your Django Unicorn
# Programs meant to be run under supervisor should not daemonize themselves (do not use --daemon)
exec ./venv/bin/gunicorn \${DJANGO_WSGI_MODULE}:application \
  --name $APPNAME \
  --workers \$NUM_WORKERS \
  --user=\$USER --group=\$GROUP \
  --bind=unix:\$SOCKFILE \
  --log-level=debug \
  --log-file=-
EOF

# Move the script to app folder
mv /tmp/gunicorn_start.sh $APPFOLDERPATH
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/gunicorn_start.sh
chmod u+x $APPFOLDERPATH/gunicorn_start.sh


# ###################################################################
# Create nginx template in $APPFOLDERPATH/nginx
# ###################################################################
mkdir -p $APPFOLDERPATH/nginx
APPSERVERNAME=$APPNAME
APPSERVERNAME+=_gunicorn
cat > $APPFOLDERPATH/nginx/$APPNAME.conf << EOF
upstream $APPSERVERNAME {
    server unix:$APPFOLDERPATH/run/gunicorn.sock fail_timeout=0;
}
server {
    listen 80;
    server_name $DOMAINNAME;

    client_max_body_size 5M;
    keepalive_timeout 5;
    underscores_in_headers on;

    access_log $APPFOLDERPATH/logs/nginx-access.log;
    error_log $APPFOLDERPATH/logs/nginx-error.log;

    location /media  {
        alias $APPFOLDERPATH/media;
    }
    location /static {
        alias $APPFOLDERPATH/static;
    }
    location /static/admin {
       alias $APPFOLDERPATH/lib/python$PYTHON_VERSION_STR/site-packages/django/contrib/admin/static/admin/;
    }

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_redirect off;
        proxy_pass http://$APPSERVERNAME;
    }
}

EOF
# make a symbolic link to the nginx conf file in sites-enabled
ln -sf $APPFOLDERPATH/nginx/$APPNAME.conf /etc/nginx/sites-enabled/$APPNAME

# ###################################################################
# Setup supervisor
# ###################################################################

# Create the supervisor application conf file
cat > /etc/supervisor/$APPNAME.conf << EOF
[program:$APPNAME]
command = $APPFOLDERPATH/gunicorn_start.sh
user = $APPNAME
autostart=true
autorestart=true
stdout_logfile = $APPFOLDERPATH/logs/gunicorn_supervisor.log
redirect_stderr = true
EOF


# ###################################################################
# Reload/start supervisord and nginx
# ###################################################################
echo "Reloading Supervisor"
supervisorctl reread
supervisorctl update

echo "Reloading Nginx"
# Reload nginx so that requests to domain are redirected to the gunicorn process
nginx -s reload || error_exit "Error reloading nginx. Check configuration files"

echo "Done!"
echo "No proceed to secure_django.sh to deploy Let's Encrypt certificates"