#!/bin/bash

sudo apt-get install i2c-tools ntpdate

#X728 RTC setting up
sudo sed -i '$ i rtc-ds1307' /etc/modules
#sudo sed -i '$ i echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-0/new_device' /etc/rc.local
sudo sed -i '$ i echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-1/new_device' /etc/rc.local
sudo sed -i '$ i hwclock -s' /etc/rc.local

#x728 Powering on /reboot /full shutdown through hardware
echo '#!/bin/bash
BATCHECK=1  # Var defined to keep system up if battery level is above 25%, var not defined to shutdown on power loss asap

# Raspberry Pi GPIO
PLD=6		# PIN 31 IN for AC power loss detection (When PLD Jumper is inserted: High=power loss | Low=Power supply normal)
SHUTDOWN=5	# PIN 29 IN for power management. aka shutdown pin (the physical button on x728)
BOOT=12		# PIN 32 OUT for power management, to signal the SBC as running. aka boot pin
LATCH=13	# PIN 33 OUT for power OFF, to signal we are shutting down. aka button pin. Note that this PIN has been changed on recent x728 revision, so PIN37 is GPIO 26 for x728 v2.0 and above, and PIN33 is GPIO 13 for X728 v1.2/v1.3
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

if [ "$1" == "--off" ]; then
		gpio_export $LATCH
		gpio_setvalue $LATCH 1
		echo "X728 Shutting down..."
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
				echo "X728 Shutting down", SHUTDOWN, ", halting the system ..."
				/sbin/shutdown
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
			/bin/sleep 1
	fi

done' > /usr/local/bin/x728pwr.sh
sudo chmod +x /usr/local/bin/x728pwr.sh

#X728 shutdown systemd service file
echo '[Unit]
Description=Start x728 power management
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

/usr/local/bin/x728pwr.sh --off
' > /lib/systemd/system-shutdown/x728softsd.sh
sudo chmod +x /lib/systemd/system-shutdown/x728softsd.sh
