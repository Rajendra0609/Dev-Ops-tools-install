#!/bin/bash

# This is a comment
echo "Hello, world!"

#############
_
git clone https://github.com/hashicorp/vault.git
cd vault
############
 make bootstrap
################
make dev

#sudo snap install vault
############
vault -version
