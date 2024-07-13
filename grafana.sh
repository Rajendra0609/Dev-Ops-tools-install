# !/bin/bash

sudo apt update

sudo apt -y upgrade

sudo apt install -y apt-transport-https
sudo apt install -y software-properties-common wget

sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key

echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list


sudo apt update

sudo apt-cache policy grafana

sudo apt install grafana

sudo systemctl start grafana-server

sudo systemctl status grafana-server

sudo systemctl enable grafana-server.service