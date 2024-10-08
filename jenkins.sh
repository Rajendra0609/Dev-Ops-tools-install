#!/bin/bash

# This is a comment
echo "Hello, world!"

# Update package lists
sudo apt update

# Install fontconfig and openjdk-17-jre
sudo apt install -y fontconfig openjdk-17-jre

###########jenkins########################
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-cache madison jenkins

#############################

echo "and java has installed!"
echo " check and install particular version of jenkins using sudo apt-get install jenkins=* -y"



sudo nano /lib/systemd/system/jenkins.service
sudo apt-get install jenkins=* -y
sudo usermod -aG docker jenkins



