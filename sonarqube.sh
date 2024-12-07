tep 1: Update the System
First, ensure your system is up-to-date:

sudo apt update
sudo apt upgrade -y
Step 2: Install Java
SonarQube requires Java 11 or 17. We will install OpenJDK 17.

sudo apt install openjdk-17-jdk -y
Verify the installation:

java -version
Step 3: Install PostgreSQL
SonarQube uses PostgreSQL as its database. Install PostgreSQL 15. Execute set of following commands:

sudo apt install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
Update and install PostgreSQL 15

sudo apt update
sudo apt install postgresql-15 -y
Now, let's configure PostgreSQL

Switch to the PostgreSQL user:

sudo -i -u postgres
Create a new user and database for SonarQube:

createuser sonar
createdb sonar -O sonar
psql
Inside the PostgreSQL shell, set a password for the sonar user:

ALTER USER sonar WITH ENCRYPTED PASSWORD 'your_password';
\q
Exit the PostgreSQL user:

exit
Step 4: Install SonarQube
Download the latest SonarQube version:

wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.5.1.90531.zip
Extract the SonarQube package:

unzip sonarqube-10.5.1.90531.zip
sudo mv sonarqube-10.5.1.90531 /opt/sonarqube
Create a SonarQube user:

sudo adduser --system --no-create-home --group --disabled-login sonarqube
Change ownership of the SonarQube directory:

sudo chown -R sonarqube:sonarqube /opt/sonarqube
Now, let's configure SonarQube

Edit the SonarQube configuration file:

sudo nano /opt/sonarqube/conf/sonar.properties
Uncomment and set the following properties:

sonar.jdbc.username=sonar
sonar.jdbc.password=your_password
sonar.jdbc.url=jdbc:postgresql://localhost/sonar
Step 5: Create a Systemd Service File
Create a new service file for SonarQube:

sudo nano /etc/systemd/system/sonarqube.service
Add the following content:

[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking

ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop

User=sonarqube
Group=sonarqube
Restart=always

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
Reload the systemd daemon and start SonarQube:

sudo systemctl daemon-reload
sudo systemctl start sonarqube
sudo systemctl enable sonarqube
Step 6: File Descriptors
Check the current limit:

ulimit -n

It should be at least 65536. To increase it, add the following to /etc/security/limits.conf:

sudo nano /etc/security/limits.conf
Add the following lines:

sonarqube   -   nofile   65536
sonarqube   -   nproc    4096
Check and set the virtual memory limit:

sudo sysctl -w vm.max_map_count=262144
To make this change permanent, add it to /etc/sysctl.conf:

sudo nano /etc/sysctl.conf
Add the following line:

vm.max_map_count=262144
Apply the changes:

sudo sysctl -p
Step 7: Configure Firewall
We need to add ports in firewall.

ufw allow 9000/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload
Step 8: Install and Configure Nginx
Install Nginx:

sudo apt install nginx -y
Create a new Nginx configuration file for SonarQube:

sudo nano /etc/nginx/sites-available/sonarqube.example.com
Note: Replace sonarqube.example.com with your domain name.

Add the following content:

server {
    listen 80;
    server_name sonarqube.example.com;

    access_log /var/log/nginx/sonarqube.access.log;
    error_log /var/log/nginx/sonarqube.error.log;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
Note: Replace sonarqube.example.com with your domain name.

Enable the new configuration:

sudo ln -s /etc/nginx/sites-available/sonarqube.example.com /etc/nginx/sites-enabled/
Test the Nginx configuration and restart Nginx:

sudo nginx -t
sudo systemctl restart nginx
Step 8: Configure HTTPS
For added security, consider configuring HTTPS for your Grafana instance. You'll need an SSL certificate for your domain. You can obtain a free SSL certificate from Let's Encrypt using Certbot.

sudo apt install certbot python3-certbot-nginx -y
Then run the following command to obtain and install the SSL certificate:

sudo certbot --nginx -d sonarqube.example.com
Note: Replace sonarqube.example.com with your domain name.

Follow the prompts to configure HTTPS with Certbot.

Step 9: Access SonarQube
Open your web browser and go to https://your_domain_or_ip. You should see the SonarQube login page. The default credentials are:

Username: admin
Password: admin
