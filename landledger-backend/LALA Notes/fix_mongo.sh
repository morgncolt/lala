#! /bin/bash


#!/bin/bash

echo "Stopping MongoDB service..."
sudo systemctl stop mongod

echo "Removing MongoDB packages..."
sudo apt remove --purge -y mongodb-org mongodb-org-server mongodb-org-mongos mongodb-org-shell mongodb-org-tools mongodb-server-core mongodb-server mongodb-mongosh mongodb-database-tools mongodb-org-database mongodb-org-database-tools-extra

echo "Cleaning up residual configuration and data files..."
sudo rm -rf /var/lib/mongodb
sudo rm -rf /var/log/mongodb
sudo rm -rf /etc/mongod.conf
sudo rm -rf /usr/bin/mongod
sudo rm -rf /usr/bin/mongos
sudo rm -rf /usr/bin/mongo*

echo "Running autoremove to clean up dependencies..."
sudo apt autoremove -y
sudo apt clean

echo "MongoDB removal completed successfully."

