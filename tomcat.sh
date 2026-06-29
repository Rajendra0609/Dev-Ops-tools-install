#!/bin/bash

# Advanced Tomcat Installation Script
# This script installs and configures Apache Tomcat with error handling, logging, and additional features.

set -e  # Exit on any error

# Configuration Variables
TOMCAT_VERSION="v10.1.56"
TOMCAT_MAJOR="10"
TOMCAT_USER="tomcat"
TOMCAT_HOME="/opt/tomcat"
LOG_FILE="/var/log/tomcat_install.log"
ADMIN_PASSWORD="admin"
DEPLOYER_PASSWORD="deploy123"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if command succeeded
check_command() {
    if [ $? -ne 0 ]; then
        log "Error: $1 failed"
        exit 1
    fi
}

# Function to install packages
install_packages() {
    log "Updating package list..."
    sudo apt update >> "$LOG_FILE" 2>&1
    check_command "apt update"

    log "Upgrading packages..."
    sudo apt upgrade -y >> "$LOG_FILE" 2>&1
    check_command "apt upgrade"

    log "Installing Java..."
    sudo apt install -y default-jdk >> "$LOG_FILE" 2>&1
    check_command "apt install default-jdk"

    java -version >> "$LOG_FILE" 2>&1
}

# Function to create Tomcat user
create_tomcat_user() {
    if id "$TOMCAT_USER" &>/dev/null; then
        log "Tomcat user already exists, skipping creation."
    else
        log "Creating Tomcat user..."
        sudo useradd -m -U -d "$TOMCAT_HOME" -s /bin/false "$TOMCAT_USER" >> "$LOG_FILE" 2>&1
        check_command "useradd"
    fi
}

# Function to download and extract Tomcat
download_and_extract_tomcat() {
    log "Downloading Tomcat $TOMCAT_VERSION..."
    cd /tmp || { log "Failed to change to /tmp"; exit 1; }

    TOMCAT_TGZ="apache-tomcat-$TOMCAT_VERSION.tar.gz"
    TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.56/bin/apache-tomcat-10.1.56.tar.gz"

    # Prefer wget, fall back to curl, or install wget if neither present
    if command -v wget >/dev/null 2>&1; then
        log "Using wget to download Tomcat"
        wget -q -O "$TOMCAT_TGZ" "$TOMCAT_URL" >> "$LOG_FILE" 2>&1
        check_command "wget download"
    elif command -v curl >/dev/null 2>&1; then
        log "wget not found, using curl to download Tomcat"
        curl -sS -fL -o "$TOMCAT_TGZ" "$TOMCAT_URL" >> "$LOG_FILE" 2>&1
        check_command "curl download"
    else
        log "Neither wget nor curl found. Installing wget..."
        sudo apt update >> "$LOG_FILE" 2>&1
        sudo apt install -y wget >> "$LOG_FILE" 2>&1
        check_command "apt install wget"
        log "Using newly installed wget to download Tomcat"
        wget "$TOMCAT_URL" >> "$LOG_FILE" 2>&1
        check_command "wget download"
    fi

    log "Downloaded $TOMCAT_TGZ"

    log "Extracting Tomcat..."
    sudo mkdir -p "$TOMCAT_HOME"
    sudo tar -xzf "apache-tomcat-$TOMCAT_VERSION.tar.gz" -C "$TOMCAT_HOME" --strip-components=1 >> "$LOG_FILE" 2>&1
    check_command "tar"

    # Clean up
    rm "apache-tomcat-$TOMCAT_VERSION.tar.gz"
}

# Function to set permissions
set_permissions() {
    log "Setting permissions..."
    sudo chown -R "$TOMCAT_USER": "$TOMCAT_HOME"
    sudo chmod +x "$TOMCAT_HOME"/bin/*.sh
}

# Function to create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    # Detect actual JAVA_HOME path for JDK (not JRE)
    JAVA_HOME_PATH=$(readlink -f /usr/bin/java | sed "s:bin/java::")
    # Use sudo tee to write the service file (avoids redirection permission issues)
    sudo tee /etc/systemd/system/tomcat.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

User=$TOMCAT_USER
Group=$TOMCAT_USER

Environment="JAVA_HOME=$JAVA_HOME_PATH"
Environment="CATALINA_PID=$TOMCAT_HOME/temp/tomcat.pid"
Environment="CATALINA_HOME=$TOMCAT_HOME"
Environment="CATALINA_BASE=$TOMCAT_HOME"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"

ExecStart=$TOMCAT_HOME/bin/startup.sh
ExecStop=$TOMCAT_HOME/bin/shutdown.sh

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

# Function to enable and start Tomcat
enable_and_start_tomcat() {
    log "Reloading systemd daemon..."
    sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1

    log "Starting Tomcat..."
    sudo systemctl start tomcat >> "$LOG_FILE" 2>&1
    check_command "systemctl start"

    log "Enabling Tomcat on boot..."
    sudo systemctl enable tomcat >> "$LOG_FILE" 2>&1
    check_command "systemctl enable"

    log "Tomcat status:"
    sudo systemctl status tomcat --no-pager
}

# Function to configure admin access
configure_admin_access() {
    log "Configuring admin access..."
    # Backup original file
    sudo cp "$TOMCAT_HOME/conf/tomcat-users.xml" "$TOMCAT_HOME/conf/tomcat-users.xml.bak"

    # Add roles and users
    sudo sed -i "/<\/tomcat-users>/i \
<role rolename=\"manager-gui\"/>\
<role rolename=\"admin-gui\"/>\
<user username=\"admin\" password=\"$ADMIN_PASSWORD\" roles=\"manager-gui,admin-gui\"/>\
<role rolename=\"manager-script\"/>\
<user username=\"deployer\" password=\"$DEPLOYER_PASSWORD\" roles=\"manager-script\"/>" "$TOMCAT_HOME/conf/tomcat-users.xml"

    # Fix Manager app context to allow remote access by commenting out the RemoteAddrValve
    MANAGER_CTX="$TOMCAT_HOME/webapps/manager/META-INF/context.xml"
    HOST_MANAGER_CTX="$TOMCAT_HOME/webapps/host-manager/META-INF/context.xml"

    comment_valve() {
        local file="$1"
        if [ ! -f "$file" ]; then
            log "File $file not found, skipping RemoteAddrValve modification."
            return 0
        fi

        # If already commented, skip
        if grep -q "<!--.*RemoteAddrValve.*-->" "$file"; then
            log "RemoteAddrValve already commented in $file, skipping."
            return 0
        fi

        # Backup before editing (only once)
        if [ ! -f "${file}.bak" ]; then
            sudo cp "$file" "${file}.bak"
            log "Backed up $file to ${file}.bak"
        fi

        # Replace any single-line that contains RemoteAddrValve with a commented version
        # Preserve leading indentation
        sudo sed -i -E 's#^([[:space:]]*)(.*RemoteAddrValve.*)#\1<!-- \2 -->#' "$file"
        if [ $? -eq 0 ]; then
            log "Commented RemoteAddrValve entries in $file"
        else
            log "Failed to comment RemoteAddrValve in $file"
        fi
    }

    comment_valve "$MANAGER_CTX"
    comment_valve "$HOST_MANAGER_CTX"
}

# Function to configure firewall
configure_firewall() {
    if command -v ufw &> /dev/null; then
        log "Configuring firewall to allow port 8080..."
        sudo ufw allow 8080 >> "$LOG_FILE" 2>&1
        sudo ufw --force enable >> "$LOG_FILE" 2>&1
    else
        log "UFW not found, skipping firewall configuration."
    fi
}

# Main execution
log "Starting Tomcat installation..."

install_packages
create_tomcat_user
download_and_extract_tomcat
set_permissions
create_systemd_service
enable_and_start_tomcat
configure_admin_access
configure_firewall

log "Restarting Tomcat to apply changes..."
sudo systemctl restart tomcat >> "$LOG_FILE" 2>&1
check_command "systemctl restart"

log "Tomcat installation completed successfully!"
log "Access Tomcat at http://localhost:8080"
log "Admin interface: http://localhost:8080/manager/html (admin/admin)"
log "Manager interface: http://localhost:8080/host-manager/html (admin/admin)"

