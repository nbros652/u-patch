#!/bin/bash
# Package updates for release

function die {
	msg="$1"
	echo -e "\n$msg\n"
	read -p "Press [Enter] to close this window."
	exit
}

pushd "$(dirname "$0")" > /dev/null

if [ ! -e pubkey ]; then
	die "ERROR: No signing key was found. Please make sure that the public key for checking signatures is saved in this directory as pubkey"
fi

pubkey=$(gpg2 pubkey | grep -oP "^pub\b.*/[0-9A-F]{8}" | cut -f2 -d "/")
i=0

# determine whether or not there are any updates available for packaging
count=$(ls -1 staging/ | wc -l)
if [ $count -eq 0 ]; then
	die "No updates to package."
fi

# list the packages in staging and query which to package
ls -1 staging/ | while read update
do
	name="$update"
	desc="$(sed -n '2p' staging/$update/install.sh)"
	printf "%04s: $name - ${desc:2}\n" "["$[++i]"]"
done
echo ""
read -p "Enter the number for the update you would like to package [1]: " selection
[ "$selection" == "" ] && selection=1

# Switch to the appropriate directory
package=$(ls -1 staging/ | sed -n "${selection}p")
pushd staging/$package > /dev/null 2>&1

# get list of files that should be added to installation package
error=0
required=""
while read line
do
	if [ -e $line ]; then
		required="$required $line"
	else 
		echo "Required file not found: $line"
		error=1
	fi
done <<< "$(cat required.txt | sed 's/ /\\ /g')"
[ $error -eq 1 ] && die "Update not packed because of missing files!"

# package and sign update
name="$(date +%s)"
echo -e "\nPlease enter the passphrase for the package signing key.\n"
success=0
tar -cJf - install.sh $required | gpg2 -s -o ../../packages/${name}_$package.tar.xz.gpg --default-key $pubkey 2> /dev/null && success=1

popd > /dev/null 2>&1
if [ $success -eq 1 ]; then
	# move from staging to packed
	mv "staging/$package" "packed/${name}_$package"

	die "$package packaged and released!"
else
	die "Something when wrong while attempting to package your update. Check your signing passphrase and try again."
fi

popd > /dev/null