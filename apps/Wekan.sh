#!/bin/sh

[ "$1" = update ] && { systemctl stop wekan; rm -rf /home/wekan/*; }
[ "$1" = remove ] && { sh sysutils/service.sh remove Wekan; userdel -rf wekan; rm -rf /usr/local/share/node-v0.10.4*; whiptail --msgbox "Wekan removed." 8 32; break; }

# https://github.com/wekan/wekan/wiki/Install-and-Update
# Defining the port
port=$(whiptail --title "Wekan port" --inputbox "Set a port number for Wekan" 8 48 "8081" 3>&1 1>&2 2>&3)

[ "$1" = install ] && { . sysutils/MongoDB.sh; }

# https://github.com/4commerce-technologies-AG/meteor
# Special Meteor + Node.js bundle for ARM
if [ -d ~./meteor ] || [ -d /usr/share/meteor ] ;then
  echo "You have Meteor installed"
elif [ $ARCHf = arm ] && [ "$1" = "" ]; then
  cd /usr/local/share
  git clone --depth 1 -b release-1.2.1-universal https://github.com/4commerce-technologies-AG/meteor

  # Fix curl CA error
  echo insecure > ~/.curlrc
  # Check installed version, try to download a compatible pre-built dev_bundle and finish the installation
  /usr/local/share/meteor/meteor -v
  rm ~/.curlrc
fi

# Add wekan user
useradd -mrU wekan

# Go to wekan user directory
cd /home/wekan

# Get the latest Wekan release
ver=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/wekan/wekan/releases/latest)

# Only keep the version number in the url
ver=${ver#*v}

# Download the arcive
download "https://github.com/wekan/wekan/releases/download/v$ver/wekan-$ver.tar.gz" "Downloading the Wekan $ver archive..."

# Extract the downloaded archive and remove it
extract wekan-$ver.tar.gz "xzf -" "Extracting the files from the archive..."

mv -f bundle/* bundle/.[^.]* .
rm wekan-$ver.tar.gz

# Dependencies needed for npm install
[ $PKG = rpm ] && $install gcc-c++ || $install g++
$install python make

if [ $ARCHf = arm ] ;then
  # Reinstall bcrypt and bson to a newer version is needed
  cd /home/wekan/programs/server/npm/npm-bcrypt && /usr/local/share/meteor/dev_bundle/bin/npm uninstall bcrypt && /usr/local/share/meteor/dev_bundle/bin/npm install bcrypt
  cd /home/wekan/programs/server/npm/cfs_gridfs/node_modules/mongodb && /usr/local/share/meteor/dev_bundle/bin/npm uninstall bson && /usr/local/share/meteor/dev_bundle/bin/npm install bson
elif [ $ARCHf = x86 ] ;then
  [ $PKG = rpm ] && $install epel-release && $install GraphicsMagick || $install graphicsmagick

  # Meteor needs Node.js 0.10.48
  download "https://nodejs.org/dist/v0.10.48/node-v0.10.48-linux-x64.tar.gz" "Downloading the Node.js 0.10.48 archive..."

  # Extract the downloaded archive and remove it
  extract node-v0.10.48-linux-x64.tar.gz "xzf - -C /usr/local/share" "Extracting the files from the archive..."
  rm node-v0.10.48-linux-x64.tar.gz
else
    whiptail --msgbox "Your architecture $ARCHf isn't supported" 8 48
fi

# Move to the server directory and install the dependencies:
cd /home/wekan/programs/server

[ $ARCHf = x86 ] && /usr/local/share/node-v0.10.48-linux-x64/bin/npm install
[ $ARCHf = arm ] && /usr/local/share/meteor/dev_bundle/bin/npm install

# Change the owner from root to wekan
chown -R wekan: /home/wekan

[ $ARCHf = x86 ] && node=/usr/local/share/node-v0.10.48-linux-x64/bin/node
[ $ARCHf = arm ] && node=/usr/local/share/meteor/dev_bundle/bin/node

# Create the systemd service
cat > "/etc/systemd/system/wekan.service" <<EOF
[Unit]
Description=Wekan Server
Wants=mongod.service
After=network.target mongod.service
[Service]
Type=simple
WorkingDirectory=/home/wekan
ExecStart=$node main.js
Environment=MONGO_URL=mongodb://127.0.0.1:27017/wekan
Environment=ROOT_URL=http://$IP:$port/ PORT=$port
User=wekan
Group=wekan
Restart=always
RestartSec=9
[Install]
WantedBy=multi-user.target
EOF

# Start the service and enable it to start at boot
systemctl start wekan
systemctl enable wekan

[ "$1" = install ] && state=installed || state=updated
whiptail --msgbox "Wekan $state!

Open http://$URL:$port in your browser" 10 64
