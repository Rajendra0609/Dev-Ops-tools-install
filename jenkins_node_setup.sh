#!/bin/bash

# Start minikube
minikube start

# Create Jenkins namespace
kubectl create namespace jenkins

# Create Jenkins service account
kubectl create sa jenkins -n jenkins

# Create role binding for Jenkins admin
kubectl create rolebinding jenkins-admin-binding --clusterrole=admin --serviceaccount=jenkins:jenkins --namespace=jenkins

# Create token for Jenkins service account
TOKEN=$(kubectl create token jenkins -n jenkins --duration=87h)

# Output the token to the user
echo "Jenkins Token: $TOKEN"

echo "Please provide this token to Jenkins to connect to the Kubernetes cluster."
