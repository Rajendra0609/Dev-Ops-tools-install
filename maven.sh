#!/bin/bash

# Update package lists
sudo apt update

# Install maven
sudo apt install -y git

###############
sudo apt update

sudo apt install -y maven

###########ansible###########
sudo apt-get update
sudo apt-get install software-properties-common
sudo apt-add-repository ppa:ansible/ansible 
sudo apt-get update
sudo apt-get install -y ansible
