#!/bin/bash

# This is a comment
echo "Hello, world!"

#############
mkdir -p $GOPATH/src/github.com/hashicorp && cd $_
git clone https://github.com/hashicorp/vault.git
cd vault
############
# make bootstrap
################
#make dev

sudo snap install vault
############
vault -version
