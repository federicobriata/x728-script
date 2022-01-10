# x728.sh
Yet another bash setup scripts for x728 v1.2/v1.3 and v2.0.

* Precondition

This script expect to work on debian and based distributions, so raspbian, armbian and similar shall be fine.
Before start this installation please ensure to have removed and cleaned everithing from your previous x728 installation especially having other service running from boot.
You know what you've allready installed, so before proceed ensure to have revert everithing.

* How to install?
```
wget https://raw.githubusercontent.com/federicobriata/x728-script/master/x728.sh
chmod +x x728.sh
sudo ./x728.sh
sudo reboot
```

* How to safe shut down?
```
sudo shutdown
```

* How to check power status?
```
sudo systemctl status x728pwr
```
