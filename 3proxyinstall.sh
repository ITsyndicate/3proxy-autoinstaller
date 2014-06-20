#!/bin/bash
#Attention! You are running this script on your risk. Internet connection could be lost.
#If you want to run it in backgrounf run ./run.sh instead.

#Enter full path to the config file
#Note that it is not 3proxy config file, this is config for this script
config=/root/3pinstaller.conf

#Ip pull ifcfg
pull_ifcfg=/etc/sysconfig/network-scripts/ifcfg-eth0-range0

#Checking input data
if [ ! -f $config ]; then
        echo "There is no config file, please create!"
        exit 1
else
        #Config and variables
        function checkconfig {
        if [[ -n "$2" ]]; then
            true
        else
            echo "Error: There is no variable $1 in your config"
            exit 1
        fi
        }
        allow=`/bin/grep "allow" $config | /bin/awk '{print $2}'`
        serverport=`/bin/grep "port" $config | /bin/awk '{print $2}'`
        userlogin=`/bin/grep "login" $config | /bin/awk '{print $2}'`
        userpassword=`/bin/grep "password" $config | /bin/awk '{print $2}'`
        pullenabled=`/bin/grep "pullenabled" $config | /bin/awk '{print $2}'`
        firsthost=`/bin/grep "first" $config | /bin/awk '{print $2}'`
        lasthost=`/bin/grep "last" $config | /bin/awk '{print $2}'`
        netmask=`/bin/grep "netmask" $config | /bin/awk '{print $2}'`
        socksenabled=`/bin/grep "socks" $config | /bin/awk '{print $2}'`
        mailuser=`/bin/grep "mailuser" $config | /bin/awk '{print $2}'`
        mailpass=`/bin/grep "mailpass" $config | /bin/awk '{print $2}'`
        usermail=`/bin/grep "usermail" $config | /bin/awk '{print $2}'`
        checkconfig $allow allow
        checkconfig $serverport port
        checkconfig $userlogin login
        checkconfig $userpassword password
        checkconfig $pullenabled pullenabled
        checkconfig $firsthost first
        checkconfig $lasthost last
        checkconfig $netmask netmask
        checkconfig $socksenabled socks
fi
#UID and GID of nobody user
NUID=`/usr/bin/id -u nobody`
NGID=`/usr/bin/id -g nobody`

#CentOS arch and version
osversion=`/bin/cat /etc/redhat-release | /bin/awk '{print $3}' | /bin/cut -f1 -d"."`
arch=`/bin/arch`
if [ "$arch" != "x86_64" ]; then
        osarch=i386
else
        osarch=$arch
fi
epelrpm=`/usr/bin/curl -s http://mirror.yandex.ru/epel/$osversion/$osarch/ | awk -F'"' '$3 ~ /epel/ {print $2}'`

#Installing 3proxy, mailx, ssmtp
/bin/rpm -Uvh http://mirror.yandex.ru/epel/$osversion/$osarch/$epelrpm
/usr/bin/yum install 3proxy -y
/bin/mv /etc/3proxy.cfg /etc/3proxy.cfg.back
/usr/bin/yum install ssmtp -y
/usr/bin/yum install mailx -y

#Ip addresses on the server
serverips=`/sbin/ifconfig | /bin/grep "inet addr" | /bin/grep -v "127.0.0.1" | /bin/awk '{print $2}' | /usr/bin/tr -d [A-Z][a-z] | /bin/sed s/://g`
firsthostsystem=`echo $serverips | head -1`
lasthostsystem=`echo $serverips | tail -1`

#Diff ip pull from config and server
if [ "$pullenabled" = "yes" ]; then
        if [[ "$firsthost" = "$firsthostsystem" && "$lasthost" = "$lasthostsystem" ]]; then
                true
        else
                if [ ! -f $pull_ifcfg ]; then
                        echo -e "IPADDR_START=$firsthost\nIPADDR_END=$lasthost\nCLONENUM_START=0\nNETMASK=$netmask" > $pull_ifcfg
                        /sbin/service network restart
                else
                        cp $pull_ifcfg /root/ifcfg-eth0-range0.backup
                        echo -e "IPADDR_START=$firsthost\nIPADDR_END=$lasthost\nCLONENUM_START=0\nNETMASK=$netmask" > $pull_ifcfg
                        /sbin/service network restart
                fi
        fi
fi
serveripschecked=`/sbin/ifconfig | /bin/grep "inet addr" | /bin/grep -v "127.0.0.1" | /bin/awk '{print $2}' | /usr/bin/tr -d [A-Z][a-z] | /bin/sed s/://g`
#Adding 3proxy autostart
/sbin/chkconfig 3proxy on &> /dev/null
/sbin/chkconfig --list 3proxy &> /dev/null
if [ $? -eq 0 ]; then
        true
else
        echo "Error: Autoinstaller stopped with errors. Could not check autostart. Please, check manual"
        exit 1
fi
#Creating IP_Pull.txt file
echo -e "$userlogin;$userpassword;$serverport\n$serveripschecked" > /IP_Pull.txt
#Configuring ssmtp and sending mail with IP List
#echo -e "root=root@localhost\nmailhub=smtp.gmail.com:587\nUseSTARTTLS=YES\nAuthUser=$mailuser\nAuthPass=$mailpass\nFromLineOverride=YES\nTLS_CA_File=/etc/pki/tls/certs/ca-bundle.crt" > /etc/ssmtp/ssmtp.conf
#/bin/mail -s "IP List" $usermail < /IP_Pull.txt

#Creating 3proxy.cfg
if [ "$socksenabled" = "yes" ]; then
    echo -e "daemon\nauth iponly strong\nusers $userlogin:CL:$userpassword\nflush\nallow $userlogin $allow\nnserver 8.8.8.8\nnscache 65536\ntimeouts 1 5 30 60 180 1800 15 60\nsetgid $NGID\nsetuid $NUID" > /etc/3proxy.cfg
    for daemonips in $serveripschecked ; do
            echo -e "socks -n -a -p$serverport -i$daemonips -e$daemonips" >> /etc/3proxy.cfg
        done
else
    echo -e "daemon\nauth iponly strong\nusers $userlogin:CL:$userpassword\nflush\nallow $userlogin $allow\nnserver 8.8.8.8\nnscache 65536\ntimeouts 1 5 30 60 180 1800 15 60\nsetgid $NGID\nsetuid $NUID" > /etc/3proxy.cfg
    for daemonips in $serveripschecked ; do
            echo -e "proxy -n -a -p$serverport -i$daemonips -e$daemonips" >> /etc/3proxy.cfg
        done
fi
#Adding firewall rules
iptables -I INPUT 1 -p tcp --dport $serverport -j ACCEPT

#Change this for grant access only from 1.2.3.4/24
#iptables -A INPUT --src 1.2.3.4/24 -p tcp --dport $serverport -j ACCEPT
#iptables -A INPUT -p tcp --dport $serverport -j REJECT

/sbin/service iptables save
#Starting 3proxy
/sbin/service 3proxy restart
exit 0
