export GRADLE_VERSION=8.10
wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -P /tmp

sudo groupadd gradle
sudo useradd -r -g gradle -d /opt/gradle -s /sbin/nologin gradle
sudo unzip -d /opt/gradle /tmp/gradle-*.zip 
sudo chown -R gradle: /opt/gradle
sudo vim /etc/profile.d/gradle.sh
#!/bin/sh
export GRADLE_HOME=/opt/gradle/gradle-*
export PATH=${GRADLE_HOME}/bin:${PATH}



sudo chmod +x /etc/profile.d/gradle.sh  
source /etc/profile.d/gradle.sh

gradle -v  
