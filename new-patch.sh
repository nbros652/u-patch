#!/bin/bash
# Create new updates in the staging area

pushd "$(dirname "$0")" > /dev/null

# query for patch information
read -p "Patch Name: " name
name="${name// /-}"
read -p "Description: " desc

# initialize patch in staging folder
mkdir staging/$name
pushd staging/$name
echo "#!/bin/bash
# $desc

" > install.sh
touch required.txt

# all done
popd > /dev/null
popd > /dev/null
exit