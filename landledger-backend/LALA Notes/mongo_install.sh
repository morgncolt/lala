#!/bin/bash

echo "Removing any existing MongoDB installations..."
sudo apt remove -y mongodb mongodb-org mongodb-server mongodb-server-core
sudo apt purge -y mongodb mongodb-org*
sudo apt autoremove -y

echo "Cleaning up residual files..."
sudo rm -rf /var/lib/mongodb
sudo rm -f /etc/mongod.conf
sudo rm -f /usr/bin/mongod /usr/bin/mongos

echo "Adding MongoDB GPG key..."
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | sudo tee /usr/share/keyrings/mongodb-server-6.0.gpg > /dev/null

echo "Updating package list..."
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.com/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

sudo apt update

echo "Installing MongoDB..."
sudo apt-get install -y mongodb-org

echo "MongoDB installation complete!"

