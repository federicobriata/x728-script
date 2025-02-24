#!/bin/bash

# This is the installer, running it will generate 2 bash script and 1 service file.

sudo apt-get install i2c-tools ntpdate

#X728 RTC setting up
sudo sed -i '$ i rtc-ds1307' /etc/modules
#sudo sed -i '$ i echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-0/new_device' /etc/rc.local
sudo sed -i '$ i echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-1/new_device' /etc/rc.local
sudo sed -i '$ i hwclock -s' /etc/rc.local

#x728 Powering on /reboot /full shutdown through hardware
echo '#!/bin/bash

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#   Copyright 2020 geekworm-com
#   Copyright 2021 Daniele Basile
#   Copyright 2022 Federico Pietro Briata

BATCHECK=1  # Var defined to keep system up if battery level is above 25%, leave this var not defined to shutdown on power loss asap

# Raspberry Pi GPIO (not tested yet with this script)
PLD=6		# PIN 31 IN for AC power loss detection (When PLD Jumper is inserted: High=power loss | Low=Power supply normal)
SHUTDOWN=5	# PIN 29 IN for power management. aka shutdown pin (the physical button on x728)
BOOT=12		# PIN 32 OUT for power management, to signal the SBC as running. aka boot pin
LATCH=13	# PIN 33 OUT for power OFF, to signal we are shutting down. aka button pin. Note that this PIN has been changed on recent x728 revision, so PIN33/GPIO13 present on X728 v1.2/v1.3 become PIN37/GPIO26 on x728 v2.0 and above.
I2CBUS=1	# 0 = /dev/i2c-0 (port I2C0), 1 = /dev/i2c-1 (port I2C1)

# Odroid C2 GPIO (with cat /sys/kernel/debug/gpio on armbian buster kernel v4.19 I found mine)
#PLD=461
#SHUTDOWN=470
#BOOT=466
#LATCH=476
#I2CBUS=0

REBOOTPULSEMINIMUM=200
REBOOTPULSEMAXIMUM=600

retval=""

I2CGET=/usr/sbin/i2cget
SYSFS_GPIO_DIR="/sys/class/gpio"

#gpio functions from ups2.sh odroid stuff
gpio_export() {
        [ -e "$SYSFS_GPIO_DIR/gpio$1" ] && return 0
        echo $1 > "$SYSFS_GPIO_DIR/export"
}

gpio_getvalue() {
	echo in > "$SYSFS_GPIO_DIR/gpio$1/direction"
        val=`cat "$SYSFS_GPIO_DIR/gpio$1/value"`
        retval=$val
}

gpio_setvalue() {
	echo out > "$SYSFS_GPIO_DIR/gpio$1/direction"
        echo $2 > "$SYSFS_GPIO_DIR/gpio$1/value"
}

if [ "$1" == "reboot" ]; then
		gpio_export $LATCH
		gpio_setvalue $LATCH 1
		/bin/sleep 4
		gpio_setvalue $LATCH 0
		exit 0
elif [ "$1" == "poweroff" ] || [ "$1" == "halt" ] ; then
		gpio_export $LATCH
		gpio_setvalue $LATCH 1
		echo "X728 Shutting down..."
		exit 0
fi

gpio_export $BOOT
gpio_setvalue $BOOT 1
gpio_export $PLD
gpio_export $SHUTDOWN

while [ 1 ]; do

	gpio_getvalue $PLD
	if [ -z ${BATCHECK+x} ];
	then
		if [ $retval -eq  1 ];
		then
			echo "Power Loss Detected. Power adapter disconnected."
			echo "X728 Shutting down in a while..."
			/sbin/shutdown
			/bin/sleep 60
		fi
	else
		DATA=$(${I2CGET} -f -y "$I2CBUS" 0x36 2 w)
		RAW=$(printf "%d\n" $(echo "${DATA}" | sed -E "s/0x([a-f0-9]{2})([a-f0-9]{2})/0x\2\1/"))
		VOLT=$(echo "scale=2; ${RAW}*78.125/1000000" | bc -l)

		DATA=$(${I2CGET} -f -y "$I2CBUS" 0x36 4 w)
		RAW=$(printf "%d\n" $(echo "${DATA}" | sed -E "s/0x([a-f0-9]{2})([a-f0-9]{2})/0x\2\1/"))
		LEVEL=$(echo "scale=2; ${RAW}/256" | bc -l)

		echo "Battery Voltage: ${VOLT}V"
		echo "Battery Capacity: ${LEVEL}%"

		if [ $(echo "${LEVEL} < 25" | bc) == 1 ] && [ $retval -eq  1 ];  # if battery level goes under 25%, shutdown gracefull
		then
			echo "Low battery. Connect the power adapter immediately"
			echo "X728 Shutting down in a while..."
			/sbin/shutdown
			/bin/sleep 60
		fi
	fi
	echo "Power Input Okay"

	gpio_getvalue $SHUTDOWN

	if [ $retval -eq 1 ];
	then
		pulseStart=$(date +%s%N | cut -b1-13)
		while [ $retval -eq 1 ]; do
			/bin/sleep 0.02
			if [ $(($(date +%s%N | cut -b1-13)-$pulseStart)) -gt $REBOOTPULSEMAXIMUM ]; then
				echo "X728 Shutting down", SHUTDOWN, ", powering OFF the system ..."
				/sbin/shutdown now
				exit 0
			fi
			gpio_getvalue $SHUTDOWN
		done
		if [ $(($(date +%s%N | cut -b1-13)-$pulseStart)) -gt $REBOOTPULSEMINIMUM ]; then
			echo "X728 Rebooting", SHUTDOWN, ", restarting the system ..."
			/sbin/reboot
			exit 0
		fi
	else
			/bin/sleep 0.02    # if you need to use the restart block leave this value, I use 2 minutes to reduce CPU usage
	fi

done' > /usr/local/bin/x728pwr.sh
sudo chmod +x /usr/local/bin/x728pwr.sh

#X728 shutdown systemd service file
echo '[Unit]
Description=x728 power management service
Requires=local-fs.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/x728pwr.sh
Restart=no

[Install]
WantedBy=basic.target' > /lib/systemd/system/x728pwr.service
sudo systemctl enable x728pwr
#sudo systemctl start x728pwr
#sudo systemctl status x728pwr

#X728 full shutdown through Software
echo '#!/bin/bash
# This script will be executed during shutdown (reboot/poweroff) chain.
# Do not execute this manually to avoid file corruption.
# More info: https://www.freedesktop.org/software/systemd/man/systemd-halt.service.html

/usr/local/bin/x728pwr.sh $1' > /lib/systemd/system-shutdown/x728softsd.sh
sudo chmod +x /lib/systemd/system-shutdown/x728softsd.sh
