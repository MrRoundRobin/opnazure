#!/bin/sh

# Script Params
# $1 = OPNScriptURI
# $2 = Primary/Secondary/SingNic/TwoNics
# $3 = Trusted Nic subnet prefix - used to get the gw
# $4 = Windows-VM-Subnet subnet prefix - used to route/nat allow internet access from Windows Management VM
# $5 = ELB VIP Address
# $6 = Private IP Secondary Server

# Check if Primary or Secondary Server to setup Firewal Sync
# Note: Firewall Sync should only be setup in the Primary Server
if [ "$2" = "Primary" ]; then
    fetch $1config-active-active-primary.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $3)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config-active-active-primary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$4_" config-active-active-primary.xml
    sed -i "" "s/www.www.www.www/$5/" config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/$6/" config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" config-active-active-primary.xml
    cp config-active-active-primary.xml /usr/local/etc/config.xml
elif [ "$2" = "Secondary" ]; then
    fetch $1config-active-active-secondary.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $3)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config-active-active-secondary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$4_" config-active-active-secondary.xml
    sed -i "" "s/www.www.www.www/$5/" config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" config-active-active-secondary.xml
    cp config-active-active-secondary.xml /usr/local/etc/config.xml
elif [ "$2" = "SingNic" ]; then
    fetch $1config-snic.xml
    cp config-snic.xml /usr/local/etc/config.xml
elif [ "$2" = "TwoNics" ]; then
    fetch $1config.xml
    fetch $1get_nic_gw.py
    gwip=$(python get_nic_gw.py $3)
    sed -i "" "s/yyy.yyy.yyy.yyy/$gwip/" config.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_$4_" config.xml
    cp config.xml /usr/local/etc/config.xml
fi

# 1. Package to get root certificate bundle from the Mozilla Project (FreeBSD)
# 2. Install bash to support Azure Backup integration
env IGNORE_OSVERSION=yes
env ASSUME_ALWAYS_YES=YES

pkg bootstrap -f
pkg update -f
pkg install -y ca_root_nss
pkg install -y bash

sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

# Add Azure waagent
fetch https://github.com/Azure/WALinuxAgent/archive/refs/tags/v2.8.0.11.tar.gz
tar -xvzf v2.8.0.11.tar.gz
cd WALinuxAgent-2.8.0.11/
python3 setup.py install --register-service --lnx-distro=freebsd --force
cd ..
ln -s /usr/local/bin/python3.9 /usr/local/bin/python

sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /etc/waagent.conf
fetch $1actions_waagent.conf
cp actions_waagent.conf /usr/local/opnsense/service/conf/actions.d

# Remove wrong route at initialization
#cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<EOL
##!/bin/sh
#route delete 168.63.129.16
#EOL
#chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute

#Adds support to LB probe from IP 168.63.129.16
# Add Azure VIP on Arp table
echo # Add Azure Internal VIP >> /etc/rc.conf
echo static_arp_pairs=\"azvip\" >>  /etc/rc.conf
echo static_arp_azvip=\"168.63.129.16 12:34:56:78:9a:bc\" >> /etc/rc.conf
# Makes arp effective
service static_arp start
# To survive boots adding to OPNsense Autorun/Bootup:
echo service static_arp start >> /usr/local/etc/rc.syshook.d/start/20-freebsd

#Download OPNSense Bootstrap and Permit Root Remote Login
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in

#OPNSense
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in
sh ./opnsense-bootstrap.sh.in -y -r "22.7"

# Clean-up
rm -rf WALinuxAgent-* actions_waagent.conf config*.xml opnsense-bootstrap.sh.in v*.tar.gz get_nic_gw.py
