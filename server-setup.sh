#!/bin/bash
#----------------------------------------------------
# Run this script from a terminal to setup a server
# machine.
#----------------------------------------------------

pushd "$(dirname "$0")" > /dev/null

# prevent a bunch of gpg2 warnings from showing later
gpg2 -K > /dev/null 2>&1
gpg2 -k > /dev/null 2>&1

TESTING=0
if [ $TESTING -eq 1 ]; then
	[ ! -d /tmp/gpg ] && mkdir /tmp/gpg
	export GNUPGHOME="/tmp/gpg"
fi

declare -A key

# customizable variables
#----------------------------------------------
key[type]='RSA'
key[size]=2048
key[name]='Patch Signer'
key[email]='none'
key[comment]='This key is used for signing u-patch patches'
key[expiration]=0	#the default of zero means no expiration
#----------------------------------------------
# end customizable variables

# configure settings for batch key generation for possible use later
function setKeyParams {
	if [ "${key[passphrase]}" == "" ]; then
		key[params]="%no-protection
		%echo Generating your signing key...
		Key-Type: ${key[type]}
		Key-Length: ${key[size]}
		Key-Usage: sign
		Name-Real: ${key[name]}
		Name-Email: ${key[email]}
		Name-Comment: ${key[comment]}
		Expire-Date: ${key[expiration]}
		%commit
		%echo done
		"
	else
		key[params]="%echo Generating your signing key...
		Key-Type: ${key[type]}
		Key-Length: ${key[size]}
		Key-Usage: sign
		Name-Real: ${key[name]}
		Name-Email: ${key[email]}
		Name-Comment: ${key[comment]}
		Expire-Date: ${key[expiration]}
		Passphrase: ${key[passphrase]}
		# Do a commit here, so that we can later print "done" :-)
		%commit
		%echo done
		"
	fi
}
setKeyParams

# remove unnecessary files
rm client-setup.sh patch.sh

# display default key parameters
function displayKeyParams {
	echo
	echo " Algorithm: ${key[type]}"
	echo "    Length: ${key[size]} bits"
	echo "     Usage: sign"
	echo "      Name: ${key[name]}"
	echo "     Email: ${key[email]}"
	echo "   Comment: ${key[comment]}"
	echo -n "Expiration: "
	[ ${key[expiration]} -eq 0 ] && echo "None" || echo "${key[expiration]}"
	echo
}

# get a new passphrase
function getNewPassphrase {
	echo -e "\nEnter a passphrase to be required for signing patches. Text will not be displayed as you type."
	read -sp "(leave blank for no passphrase): " key[passphrase]
	echo
	if [ "${key[passphrase]}" != "" ]; then
		#verify passphrase
		read -sp "confirm passphrase: " confirm
		echo
		if [ "$confirm" != "${key[passphrase]}" ]; then
			echo -e "\nPasswords don't match! Try again."
			getNewPassphrase
		fi
	fi
}

# make a new key
function createKey {
	getNewPassphrase
	setKeyParams
	echo -e "\nPlease wait while your key is generated. If this takes a while, to generate some entropy, try performing some other actions on your computer while you wait."
	id=$(gpg2 --batch --gen-key <<< "${key[params]}" 2>&1 | grep -oP "key [0-9A-Z]{8}" | cut -f 2 -d ' ')
	storePubKey $id
	echo "Key generation done"
}

# save the selected public key to the working directory
# this can then be retrieved by clients
function storePubKey {
	echo "Saving public key $1"
	[ -e pubkey ] && rm -f pubkey
	gpg2 --export -a $1 > pubkey
	sleep 1
	chmod -w pubkey
}

# Ask user if a new key should be generated
function queryCreateKey {
	displayKeyParams
	echo "Would you like to create one with the above settings?"
	read -p "[Y/n]: " doCreate
	[ "$doCreate,," != "n" ]	&& doCreate="y"
	
	if [ "$doCreate" == "y" ]; then
		createKey
	fi
}

# pick a key to use for package signing
function setKey {
	echo -n "To secure updates, packages must be signed. "

	# compose list of key ids
	declare -A ids
	i=1
	while read line
	do
		ids[$i]=${line: -8}
		let $[i++]
	done <<< "$(gpg2 -K | grep -oP "^sec\b.*/[0-9A-F]{8}")"

	# compose a list of keys, each identified by key id
	existingKeys="$(
		i=1
		gpg2 --list-secret-keys | while read line
		do
			grep -P "^(sec)|(uid)" <<< "$line" > /dev/null 2>&1 && \
				printf "%05s: %s\n" "[${ids[$i]}]" "$(grep -P "^(sec)|(uid)" <<< "$line")"
			grep -P "^$" <<< "$line" && let $[i++];done
	)"

	# Let's start by assuming no key should be created
	doCreate=n
	if [ $(wc -l <<< "$existingKeys") -gt 1 ]; then
		# there are already keys; see if the user wants to use one
		echo "Would you like to use one of the following GPG keys for signing?"
		echo -e "\n$existingKeys\n"
		read -p "Enter the ID of your selection or enter 0 (zero) to create a new key: " id
		
		# only check for valid id if zero was not entered
		[ "$id" != "0" ] && id=$(echo "${ids[*]}" | grep -oP "$id")
		
		if [ "$id" == "0" ]; then
			# looks like the user wants to create a new key
			queryCreateKey
		elif [ "$id" == "" ]; then
			# invalid input; try again
			echo "You did not enter a valid ID. Please try again."
			setKey
		else
			# an existing key was selected, save the public key
			storePubKey $id
		fi
		
		
	else 
		# no keys currently exist; ask if we should make one
		echo -n "No keys currently exist. "
		queryCreateKey
	fi

}

# create some directories we'll work from
mkdir packages packed staging
htaccess="order deny,allow
deny from all"
echo "$htaccess" | tee packages/.htaccess | tee staging/.htaccess > /dev/null

# pick a key for package signing
setKey

# install php & apache for user
install=""
if [ $(which php) ]; then
	echo "PHP is already installed"
else
	install="php libapache2-mod-php $install"
fi
if [ $(which apache2) ]; then
	echo "Apache2 is already installed"
else
	install="apache2 $install"
fi
if [ "$install" != "" ]; then
	echo "The following required packages appear to be missing. Would you like to install them now?"
	echo "$install"
	read -p "Install? [Y/n]: " opt
	[ "${opt,,}" != "n" ] && sudo apt-get update && sudo apt-get -y install $install
fi

# configure apache to use .htaccess file
begin=$(grep -nP "<Directory.*/var/www/>" /etc/apache2/apache2.conf | cut -f 1 -d ":")
if [ "$begin" != "" ]; then
	echo
	read -p "Would you like to restrict web access to packaged patches only? (Recommended) [Y/n]: " opt
	if [ "${opt,,}" != "n" ]; then
		end=$(grep -nP "</Directory>" /etc/apache2/apache2.conf | cut -f1 -d: | awk '$1>164 {print $1}' | head -n1)
		snip="$(awk "NR >= $begin && NR <= $end" /etc/apache2/apache2.conf)"
		line=$[ $(grep -n "AllowOverride" <<<  "$snip" | cut -f 1 -d ":") - 1 + begin ]
		sudo sed -i "${line}s/.*/	AllowOverride ALL/" /etc/apache2/apache2.conf
		echo ".htaccess file enabled for /var/www/*"
	else
		echo "You may not be able to control web access with .htaccess files. This is not recommended."
	fi
else
	echo "We weren't able to turn enable the .htaccess file. You may need to do this manually."
fi

# move current directory to html dir
curDir=$(basename $(pwd))
path=$(pwd)
cd ..
sudo mv "$curDir" /var/www/html/u-patch_updates > /dev/null 2>&1
if [ ! -d /var/www/html/u-patch_updates ]; then
	echo "It would appear that the web directory /var/www/html does not exist on your server."
	echo "Please manually move this directory to a folder called u-patch_updates in your web root."
	echo "Until you do this, your clients will not recognize this server."
else 
	echo "Moved $path to /var/www/html/u-patch_updates, renaming $curDir as u-patch_updates"
	rm /var/www/html/u-patch_updates/server-setup.sh
	echo -e "\nDeleted setup script\n"
	ln -s /var/www/html/u-patch_updates $path
fi

read -sp "Finished! Press [Enter] to close this window."
echo

popd > /dev/null