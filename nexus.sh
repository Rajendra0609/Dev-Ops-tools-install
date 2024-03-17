sudo apt install openjdk-8-jdk



sudo wget https://download.sonatype.com/nexus/3/latest-unix.tar.gz
sudo tar -xvzf latest-unix
sudo mv nexus-* /opt/nexus
sudo adduser nexus
sudo chown -R nexus:nexus /opt/nexus
sudo chown -R nexus:nexus /opt/sonatype-work
sudo vim /opt/nexus/bin/nexus.rc
run_as_user=”nexus”
sudo vim /opt/nexus/bin/nexus.vmoptions
sudo vim /etc/systemd/system/nexus.service

[Unit]
Description=nexus service
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
User=nexus
Group=nexus
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
User=nexus
Restart=on-abort
[Install]
WantedBy=multi-user.target

sudo systemctl enable nexus

sudo systemctl start nexus

sudo systemctl status nexus

tail -f /opt/sonatype-work/nexus3/log/nexus.log