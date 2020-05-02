#!/bin/bash

source ./common_funcs.sh

check_root

PIP="pip3"

LINUX_PREREQ=('git' 'build-essential' 'python3-dev' 'python3-pip' 'nginx' 'postgresql' 'libpq-dev' 'redis-server' 'supervisor')

PYTHON_PREREQ=('virtualenv' )

# Test prerequisites
echo "Checking if required packages are installed..."
declare -a MISSING
for pkg in "${LINUX_PREREQ[@]}"
    do
        echo "Installing '$pkg'..."
        apt-get -y install $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing system package '$pkg'"
            exit 1
        fi
    done

for ppkg in "${PYTHON_PREREQ[@]}"
    do
        echo "Installing Python package '$ppkg'..."
        $PIP install $ppkg
        if [ $? -ne 0 ]; then
            echo "Error installing python package '$ppkg'"
            exit 1
        fi
    done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo "Following required packages are missing, please install them first."
    echo ${MISSING[*]}
    exit 1
fi

echo "All required packages have been installed!"

