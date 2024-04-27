wget https://services.gradle.org/distributions/gradle-${VERSION}-bin.zip -P /tmp

sudo unzip -d /opt/gradle /tmp/gradle-${VERSION}-bin.zip

sudo nano /etc/profile.d/gradle.sh

export PATH=$PATH:/opt/gradle/

sudo chmod +x /etc/profile.d/gradle.sh

source /etc/profile.d/gradle.sh

gradle -v

