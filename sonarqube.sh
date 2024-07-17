#!/bin/bash

# Install OpenJDK 11
sudo apt-get install openjdk-11-jdk -y

# Install and Configure PostgreSQL
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
sudo wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -
sudo apt install postgresql postgresql-contrib -y
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo passwd postgres

# Switch to postgres user
su - postgres
createuser sonar
psql
ALTER USER sonar WITH ENCRYPTED password 'raja';
CREATE DATABASE sonarqube OWNER sonar;
GRANT ALL PRIVILEGES ON DATABASE sonarqube to sonar;
\q

# Return to non-root sudo user account
exit

# Download and Install SonarQube
sudo apt-get install zip -y
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.6.92038.zip
sudo unzip sonarqube-9.9.6.92038.zip
sudo mv sonarqube-9.9.6.92038 /opt/sonarqube

# Add SonarQube Group and User
sudo groupadd sonar
sudo useradd -d /opt/sonarqube -g sonar sonar
sudo chown sonar:sonar /opt/sonarqube -R

# Configure SonarQube
sudo nano /opt/sonarqube/conf/sonar.properties
# Add the following lines:
sonar.jdbc.username=sonar
sonar.jdbc.password=my_strong_password
sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube
sudo nano /opt/sonarqube/bin/linux-x86-64/sonar.sh
# Add the following line:
RUN_AS_USER=sonar

# Setup Systemd service
sudo nano /etc/systemd/system/sonar.service
# Add the following lines:
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking

ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop

User=sonar
Group=sonar
Restart=always

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
sudo systemctl enable sonar
sudo systemctl start sonar
sudo systemctl status sonar

# Modify Kernel System Limits
sudo nano /etc/sysctl.conf
# Add the following lines:
vm.max_map_count=262144
fs.file-max=65536
ulimit -n 65536
ulimit -u 4096
sudo reboot
