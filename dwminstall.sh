#!/usr/bin/env bash

# XSessions and dwm.desktop
if [[ ! -d /usr/share/xsessions ]]; then
    sudo mkdir /usr/share/xsessions
fi

cat > ./temp << "EOF"
[Desktop Entry]
Encoding=UTF-8
Name=dwm
Comment=Dynamic window manager
Exec=dwm
Icon=dwm
Type=XSession
EOF
sudo cp ./temp /usr/share/xsessions/dwm.desktop;rm ./temp


# Creating directories
mkdir /home/amar/.config/suckless

#sudo apt install -y xorg-dev sxhkd

# Move install directory, make, and install
cd /home/amar/.config/suckless
tools=( "dwm" "dmenu" "slstatus" "slock" )
for tool in ${tools[@]}
do 
	git clone git://git.suckless.org/$tool
	cd /home/amar/.config/suckless/$tool;make;sudo make clean install;cd ..
done
