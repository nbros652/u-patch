# u-patch: Ur Patches Applied To Computers Herewith
Distribute bash script-based patches to multiple Ubuntu systems.

Setup:
---
I highly recommend reading through everything here before trying to setup U-PATCH. Nevertheless, I'm starting out with the setup instructions. Whether you're setting this up in server mode or client mode, the first thing you need to do is clone all of the files in this repository using the [Clone or Download] button on the [main page](https://github.com/nbros652/u-patch).

Once you've downloaded all of the files, you're left with one of two primary tasks. To set up a U-PATCH server, run the server-setup.sh script. To set up a U-PATCH client, run the client-setup.sh script. From there, just follow the prompts until either of the scripts has completed its tasks. Assuming these complete as expected, you should be up and running. You'll want to configure your sever first, as the client-setup.sh script requires you to enter the server's domain name or IP address.

Built for and tested on Ubuntu 16.04.3:
---
These scripts have been built for and tested on Ubuntu 16.04.3. They should generally work on other versions as well, but depending on the versions of PHP and Apache2 available for those versions, small modifications may be necessary. With a little reworking, I'm sure you could get these working on other Linux distributions as well.

Background:
---
I manage a fair number of Ubuntu Linux Desktop systems throughout a building. These are used by more than 30 different individuals on a regular basis. Occasionally, I find that I need to make updates to these systems from time to time, and going around to each computer, or even logging in remotely to apply updates is not a good option. My solution was to create a patch systems that would allow me to write bash scripts that would perform the required changes and host these scripts on a server. Over the years, it has changed a little bit, and it's undergone one complete rewrite, and there's still room for improvement.

The System:
---
The update mechanism is composed of a server component and a client component. The server component is used to create and host patches. The client component check for new patches and applies them.

The server utilizes the following folders and files of interest.
* server-setup.sh: This script configures a computer to run as the server.
* index.php: This is the page that clients hit for a list of available updates.
* new-update.sh: This script intializes new patches.
* package.sh: This script packages and signs updates that have been written and makes them available to clients.
* staging (folder): When a new patch is initialized, everything needed for that patch is created here.
* packed (folder): All patches that have been released are stored here un uncompressed, unsigned form
* packages (folder): This is where compressed, signed patches are stored. Patches in this folder are visible to clients.
* .httaccess files: There are a handful of these throughout that help to restrict web access to only content that clients need.

The client utilizes the following file of interest.
* client-setup.sh: This script will configure a system to run as a client.
* patch.sh: This script runs on the client, looking for and installing patches hosted by the server.

General flow:
---
Patches are created on the server with the **new-patch.sh** script. This creates a folder in the staging area with the patch name. Inside this folder are two files, an install.sh file and a required.txt file.

Should the patch require additional files, like a .deb file to install or something similar, those files should be dropped in folder created for the patch, and the names of those files should be added (one file name per line) to the **required.txt** file. The **required.txt** is a manifest of all files to compress with the **install.sh** script which is included by default.

With all of the files in place, all commands to perform the patch should be placed in the **install.sh file**. Compose this file carefully! *If the **install.sh** script does not run successfully on clients, the client will know, and it will prevent all further patches from being installed until the patch that exited with an error is fixed*

Once you've finished writing your **install.sh**, run the **package.sh** script. This will take you through the steps of selecting a patch to package. Once selected, your patch will be compressed, signed, and released. When a package is released, the current timestamp (seconds since epoch) will be prepended to the folder name containing your patch and that folder will be moved to the packed directory. Additionally, the install.sh plus any files listed in the **required.txt** file will be compressed as a .tar.xz file, named according to the timestamp and patch name (e.g. 1521018183_my-first-patch.tar.xz), signed, and dumped into the packages folder.

*Again, be very careful in composing your install.sh file! If running **install.sh && echo error** would return the word **error**, then your clients will hang on this patch and they will not be able to install any patches that were packaged at a later date.*

---

On the client side, the **patch.sh** script is run to fetch a list of patches from the server. Each client tracks the last update that it successfully installed. Since these updates are named using timestamps, the client compares the timestamp of the last update to each of the patches in order from least to greatest. When it finds a patch that has not been installed, it checks the signature on that patch. If the signature is good, then installation of the patch is attempted. If the patch installs correctly, the client update its record of the last successfully installed patch and will move onto the next patch or quit if there are no more patches. If a patch fails to install, the client will stop trying to install any further patches and the client's record of the last installed patch will not be updated to match the patch that exited with an error.

When **patch.sh** is run on a client, the client checks to see if it has a public key to use for signature verification. If it does not, it will pull the **pubkey** file from the server that what generated when the server was configured. Note that it is recommended here for security sake that you should probably be using HTTPS or some other secure mechanism to get this key as it will be used to verify the authenticity of patches.

The **client-setup.sh** script will configure **patch.sh** to run as root at regular intervals

--- 

There is plenty of room for improvement here. For example, it would be nice for clients to report failed attempts at patch installation. It might also be nice to implement some kind of update prerequisite feature. Right now, the system refuses to allow installation of all patches newer than any given patch that exited with an error. This is to prevent installation of patches that rely on previous patches that may not have been successfully installed.
