#!/bin/bash

DEBUG=1
cleared=0
function debug {
	[ $cleared -eq 0 ] && clear && cleared=1
	[ $DEBUG -eq 1 ] && echo "[$(date +%H%M%S)]: $@" 1>&2
}

pushd "$(dirname "$0")" > /dev/null
workingDir="$(pwd)"

# server from which to pull patches
server=""
if [ "$server" == "" ]; then
	echo "ERROR: No update server has been configured. Please set the server variable equal to the domain name or IP address of your U-PATCH server."
	echo "Quitting"
	exit
fi

# check for public key
if [ ! -e pubkey ]; then
	# uh-oh, this client doesn't have a public key to use for signature verfication. Retrieve from server.
	hit=0
    wget -T 10 -t 1 https://$server/u-patch_updates/pubkey > /dev/null 2>&1 && hit=1 && method="https"
    [ $hit -eq 0 ] && wget -T 10 -t 1 http://$server/u-patch_updates/pubkey > /dev/null 2>&1 && hit=1 && method="http"

    if [ $hit -eq 0 ]; then
        echo "There was an error retrieving the public key used for package signature verfication from $server"
    else
        if [ "$method" == "http" ]; then
            long=$(gpg2 --with-fingerprint pubkey | grep fingerprint | tr -d ' ' | cut -f2 -d "=")
            short=${long: -8}
            echo "WARNING!: the public key for signature verification was fetched using http. This is insecure, and the fingerprint of the key should be verified!"
            echo "The fingerprint of the downloaded key is $long or $short for short"
			echo "Continuing with unverified public key."
			gpg2 --import pubkey > /dev/null 2>&1
        fi
    fi
fi

#get record of last update
debug "getting record of last installed update"
[ ! -e "lastUpdate" ] && echo 0 > "lastUpdate"
lastUpdate=$(cat lastUpdate)
lastUpdateTimestamp=$(grep -oP "^\d+" <<< "$lastUpdate")
debug "last update: $lastUpdate"

#get a list of available updates
debug "getting a list of updates"
updates=$(wget -O - http://$server/u-patch_updates 2> /dev/null | grep -oP "^\d+.*" | uniq | sort | awk -F '_' -v n=$lastUpdateTimestamp '$1 > n  {print $0}')

# implement ignored updates list for updates with signatures that don't match

debug "Update list ...

available updates:
--------------
${updates:-NO UPDATES AVAILABLE}
--------------
"

#iterate over available updates, installing as necessary
broken=0
for update in $updates
do
	if [ $broken -eq 0 ]; then
		debug "Installing $update"
		
		# create a temp directory to work in
		debug "creating temp directory to download update to and switching to that directory"
		dir=$(mktemp -d)
		pushd $dir > /dev/null 2>&1
		
		# download and extract
		debug "downloading $update"
		wget http://$server/u-patch_updates/packages/$update 2> /dev/null
		debug "checking patch signature"
		gpg2 --verify $update 2> /dev/null && gpg2 -do - $update 2> /dev/null | tar -xJf - && sig=good || sig=bad
		
		if [ "$sig" == "good" ]; then
			# install the update
			debug "The signature's good! ... installing $update"
			/bin/bash install.sh || broken=1
			if [ $broken -eq 0 ]; then
				debug "$update installed"
				echo $update > "$workingDir/lastUpdate"
			else
				debug "update $update failed to install"
			fi
		else
			debug "ERROR: Bad signature! Skipping installation of $update and moving on to the next update!"
			echo "$update (not installed)" > "$workingDir/lastUpdate"
		fi
		
		# clean up
		debug "removing temp directory"
		popd > /dev/null 2>&1
		rm -fr $dir
		
	fi
done

[ $broken -eq 1 ] && debug "Done, but not all updates were installed" || debug "updates finished"

popd > /dev/null