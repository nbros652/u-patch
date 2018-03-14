#!/bin/bash
#----------------------------------------------------
# Run this script from a terminal to setup a client
# machine.
#----------------------------------------------------

pushd "$(dirname "$0")" > /dev/null

DEBUG=1
function debug {
	[ $DEBUG -eq 1 ] && echo "[$(date +%H%M%S)]: $@" 1>&2
}

debug "Started U-PATCH client setup"

gpg2 -k > /dev/null 2>&1

# remove all unnecessary stuff
debug "Deleting everyting except patch.sh"
find -type f ! -iname "patch.sh" ! -iname "client-setup.sh" -exec rm '{}' \;

# query for server information
function getServerInfo {
    echo
    echo "I need to know how to access the U-PATCH update server."
    read -p "Please enter the server domain name or IP address: " server
    echo -e "\nPlease wait while I attempt to contact $server"

    hit=0
    wget -T 10 -t 1 https://$server/u-patch_updates/pubkey > /dev/null 2>&1 && hit=1 && method="https"
    [ $hit -eq 0 ] && wget -T 10 -t 1 http://$server/u-patch_updates/pubkey > /dev/null 2>&1 && hit=1 && method="http"

    if [ $hit -eq 0 ]; then
        echo "I couldn't find that server, or it has not yet been configured as a U-PATCH server."
        read -p "Would you like to continue anyway using $server? [y/N]: " opt
        [ "${opt,,}" != "y" ] && getServerInfo
    else

        if [ "$method" == "http" ]; then
            long=$(gpg2 --with-fingerprint pubkey 2> /dev/null | grep fingerprint | tr -d ' ' | cut -f2 -d "=")
            short=${long: -8}
            echo -e "\nWARNING!: the public key for signature verification was fetched using http. This is insecure, and the fingerprint of the key should be verified!"
            echo -e "The fingerprint of the downloaded key is $long or $short for short\n"
            read -p "Do you want to use this key unverified? [Y/n]: " use
            if [ "${use,,}" == "n" ]; then
                rm pubkey && echo "Deleted unverified public key"
            fi
        fi
    fi
}
getServerInfo

# edit the patch.sh file to point to the U-PATCH server
sed -i "s/server=.*/server='$server'/" patch.sh 

# import the public key to keyring
[ -e pubkey ] && gpg2 --import pubkey > /dev/null 2>&1

# set patch.sh to run on an automated schedule
echo -e "\nWe're going to install a job in root's crontab. For that we will need your password..."
path=$(pwd)
echo "0       *       *       *       *       $path/patch.sh" | sudo tee -a /var/spool/cron/crontabs/root > /dev/null
echo -e "\n
A cronjob was added to root's crontab to run patch.sh hourly. If you would like to change this, run 'sudo crontab -e'."

# make sure the patch.sh script is executable
chmod +x patch.sh

# remove this setup script
rm client-setup.sh
echo -e "\nClient setup script removed.\n"

read -sp "Setup Finished! Press [Enter] to close this window"
echo

popd > /dev/null