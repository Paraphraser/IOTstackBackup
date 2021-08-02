# IOTstack Backup and Restore

This project documents my approach to backup and restore of [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). My design goals were:

1. Avoid the double-compression implicit in the official backup scripts:

	* An InfluxDB portable backup produces .tar.gz files. Simply collecting those into a separate .tar is more efficient than recompressing them into a .tar.gz.

2. Provide a variety of post-backup methods to copy backup files from a "live" Raspberry Pi to another machine on the local network and/or to the cloud. With appropriate choices, three levels of backup are possible:

	* Recent backups are stored on the "live" RPi in `~/IOTstack/backups/`
	* On-site copies are stored on another machine on the local network
	* Off-site copies are stored in the cloud (eg Dropbox).

3. More consistent and `cron`-friendly logging of whatever was written to `stdout` and `stderr` as the backup script ran.
4. Efficient restore of a backup, including in a "bare-metal" restore.

My scripts may or may not be directly useful in your situation. They are intended less as a drop-in replacement for the official backup script than they are as an example of an approach you might consider and adapt to your own needs.

In particular, these scripts will never be guaranteed to cover the full gamut of container types supported by [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack).

The scripts *should* work "as is" with any container type that can be backed-up safely by copying the contents of its `volumes` directory _while the container is running_. I call this the ***copy-safe*** property.

Databases (other than SQLite) are the main exception. Like the official backup script upon which it is based, `iotstack_backup` handles `InfluxDB` properly, omits `nextcloud`, `postgres` and `mariadb` entirely, and completely ignores the problem for any container which is not *copy-safe*.

When I first developed these scripts, there was no equivalent for `iotstack_restore` in [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). That was a gap I wanted to rectify. Running my `iotstack_restore` replaces the contents of the `services` and `volumes` directories, then restores the `InfluxDB` databases properly. Fairly obviously, `nextcloud` will be absent but any other non-*copy-safe* container may well be in a damaged state.

If you are running `nextcloud` or any container type which is not *copy-safe*, it is up to you to come up with an appropriate solution. Most database packages have their own backup & restore mechanisms. It is just a matter of working out what those are, how to implement them in a Docker environment, and then bolting that into your backup/restore scripts.

## Contents

- [setup](#setup)
	- [Download repository](#downloadRepository)
	- [Install scripts](#installScripts)
	- [Install dependencies](#installDependencies)
	- [The configuration file](#configFile)
		- [method: ](#keyMethod)
		- [prefix: ](#keyPrefix)
		- [retain: ](#keyRetain)
	- [Choose your backup and restore methods](#chooseMethods)
		- [*scp*](#scpOption)
		- [*rsync*](#rsyncOption)
		- [*rclone* (Dropbox)](#rcloneOption)
		- [mix and match](#mixnmatch)
	- [Check your configuration](#configCheck)
- [The backup side of things](#backupSide)
	- [iotstack\_backup\_general](#iotstackBackupGeneral)
	- [iotstack\_backup\_influxdb](#iotstackBackupInfluxdb)
	- [iotstack\_backup](#iotstackBackup)
- [The restore side of things](#restoreSide)
	- [iotstack\_restore\_general](#iotstackRestoreGeneral)
	- [iotstack\_restore\_influxdb](#iotstackRestoreInfluxdb)
	- [iotstack\_restore](#iotstackRestore)
- [Bare-metal restore](#bareMetalRestore)
- [iotstack\_reload\_influxdb](#iotstackReloadInfluxdb)
- [Notes](#endNotes)
	- [about *runtag*](#aboutRuntag)
	- [about InfluxDB backup and restore commands](#aboutInfluxCommands)
	- [about InfluxDB database restoration](#aboutInfluxRestore)
	- [using cron to run iotstack\_backup](#usingcron)
	- [periodic maintenance](#periodicMaintenance)

## <a name="setup"> setup </a>

### <a name="downloadRepository"> Download repository </a>

Strictly speaking, this repository can be cloned anywhere on your Raspberry Pi. However, I recommend the `~/.local` directory:

```
$ mkdir -p ~/.local
$ cd ~/.local
$ git clone https://github.com/Paraphraser/IOTstackBackup.git IOTstackBackup
```

### <a name="installScripts"> Install scripts </a>

Run the following commands:

```
$ cd ~/.local/IOTstackBackup
$ ./install_scripts.sh
```

Notes:

* If `~/.local/bin` already exists, the scripts are copied into it.
* If `~/.local/bin` does not exist, the Unix PATH is searched for an alternative directory that is under your home directory. If the search:
	- *succeeds*, the scripts are copied into that directory
	- *fails*, `~/.local/bin` is created and the scripts are copied into it.

Check the result by executing:

```
$ which iotstack_backup
```

You will either see a path like:

```
/home/pi/.local/bin/iotstack_backup
```

or get "silence". If `which` does not return a path, try logging-out and in again to give your `~/.profile` the chance to add `~/.local/bin` to your search path, and then repeat the test.

> There are many reasons why a folder like `~/.local/bin` might not be in your search path. It is beyond the scope of this document to explore all the possibilities. Google is your friend.

### <a name="installDependencies"> Install dependencies </a>

Make sure your system satisfies the following dependencies:

```
$ sudo apt install -y rsync python3-pip python3-dev
$ curl https://rclone.org/install.sh | sudo bash
$ sudo pip3 install -U niet
```

Some (or all) may be installed already on your Raspberry Pi. Some things to note:

1. You can also install *rclone* via `sudo apt install -y rclone` but you get an obsolete version. It is better to use the method shown here.
2. *niet* is a YAML parser (analogous to *jq* for JSON files).

### <a name="configFile"> The configuration file </a> (!! new !!)

The `iotstack_backup` and `iotstack_restore` scripts depend on a configuration file at the path:

```
~/.config/iotstack_backup/config.yml
```

A script is provided to initialise a template configuration but you will need to edit the file by hand once you choose your backup and restore methods. The configuration file follows the normal YAML syntax rules. In particular, you must use spaces for indentation. You must not use tabs.

#### <a name="keyMethod"> method: </a>

What "method" means depends on your perspective. For **backup** operations you have a choice of:

* SCP (file-level copying)
* RSYNC (folder-level synchronisation)
* RCLONE (folder-level synchronisation)

For **restore** operations, your choices are:

* SCP (file-level copying)
* RSYNC (file-level copying; actually uses *scp*)
* RCLONE (file-level copying)

Although the templates assume you will use the same method for both backup and restore, this is not a requirement. You are free to [mix and match](#mixnmatch).

#### <a name="keyPrefix"> prefix: </a>

The "prefix" keyword means:

> the path to the **parent** directory of the actual backup directory on the remote machine.

Using *scp* as an example, suppose:

* the remote machine has the name "host.domain.com"
* you login on that machine with user name "user"
* you have created the directory "IOTstackBackups" in that user's home directory.

In an *scp* command, you would refer to that remote destination as:

```
user@host.domain.com:IOTstackBackups
```

Similarly, if you set up an *rclone* connection to Dropbox, you might refer to the remote `IOTstackBackups` folder like this:

```
dropbox:MyIOTstackBackups
```

Both of those are *prefixes*. When `iotstack_backup` runs, it appends the HOSTNAME environment variable to the prefix to form the path to the actual backup directory. For example, suppose the Raspberry Pi has the name `iot-hub`. Appending the host name to the two example prefixes above results in:

```
user@host.domain.com:IOTstackBackups/iot-hub
dropbox:MyIOTstackBackups/iot-hub
```

The `iot-hub` directory on the remote system is where the backups from the host named `iot-hub` will be stored.

In other words, the hostname is used as a *discriminator*. If you have more than one Raspberry Pi, you can safely use the same [configuration file](#configFile) on each Raspberry Pi without there being any risk of your backups becoming co-mingled or otherwise leading to confusion.

The `iotstack_restore` command has complementary logic. It can either derive the hostname from the *runtag* or you can pass the correct value as a parameter.

Notes:

* Both the path portion of the prefix (eg `IOTstackBackups`) and all per-machine subdirectories (eg `iot-hub`) should exist on the remote machine **before** you run `iotstack_backup` for the first time on any Raspberry Pi.
* The *rclone* method *will* automatically create missing directories on the remote host but the *scp* and *rsync* methods will **not**. You have to create the directories by hand.

#### <a name="keyRetain"> retain: </a>

The `retain` keyword is an instruction to the backup script as to how many previous backups it should retain *on the Raspberry Pi*.

This, in turn, will *influence* the number of backups retained on the remote host if you choose either the *rclone* or *rsync* options.

To repeat: `retain` only affects what is retained on the Raspberry Pi. 

### <a name="chooseMethods"> Choose your backup and restore methods </a>

#### <a name="scpOption"> *scp* </a>

*scp* (secure copy) saves the results of *this* backup run. Backup files copied to the remote will be retained on the remote until *you* take some action to remove them.

You can install a template [configuration file](#configFile) for *scp* like this:

```
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh SCP
``` 

The template is:

```
backup:
  method: "SCP"
  prefix: "user@host.domain.com:path/to/backups"
  retain: 8

restore:
  method: "SCP"
  prefix: "user@host.domain.com:path/to/backups"
```

Field definitions:

* `user` is the username on the remote computer.
* `host.domain.com` can be a hostname, a fully-qualified domain name, or the IP address of the remote computer. The remote computer does **not** have to be on your local network, it simply has to be reachable. Also, given an appropriate entry in your `~/.ssh/config`, you can reduce `host.domain.com` to just `host`.
* `path/to/backups` is the path to the target directory on the remote computer. The path can be absolute or relative. The path is a [prefix](#keyPrefix).

You should test connectivity like this:

1. Replace the right hand side with your actual values and execute the command:

	```
	$ PREFIX="user@host.domain.com:path/to/backups"
	```
	
	Notes:
	
	* The right hand side should not contain embedded spaces or other characters that are open to misinterpretation by `bash`.
	* `path/to/backups` is assumed to be relative to the home directory of `user` on the remote machine. You *can* use absolute paths (ie starting with a "/") if you wish.
	* all directories in the path defined by `path/to/backups` must exist and be writeable by `user`.

2. Test sending from this host to the remote host:

	```
	$ touch test.txt
	$ scp test.txt "$PREFIX/test.txt"
	$ rm test.txt
	```

3. Test fetching from the remote host to this host:

	```	
	$ scp "$PREFIX/test.txt" ./test.txt
	$ rm test.txt
	```

Your goal is that both of the *scp* commands should work without prompting for passwords or the need to accept fingerprints. Follow [this tutorial](ssh_tutorial.md) if you don't know how to do that.

Once you are sure your working PREFIX is correct, copy the values to the [configuration file](#configFile).

#### <a name="rsyncOption"> *rsync* </a>

*rsync* uses *scp* but performs more work. The essential difference between the two methods is what happens during the final stages of a backup:

* *scp* copies the individual **files** produced by *that* backup to the remote machine; while
* *rsync* synchronises the `~/IOStack/backup` **directory** on the Raspberry Pi with the backup folder on the remote machine.

The `~/IOStack/backup` directory is trimmed at the end of each backup run. The trimming occurs **after** *rsync* runs so, in practice the backup folder on the remote machine will usually have one more backup than the Raspberry Pi.

You can install a template [configuration file](#configFile) for *rsync* like this:

```
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh RSYNC
``` 

The template is:

```
backup:
  method: "RSYNC"
  prefix: "user@host.domain.com:path/to/backups"
  retain: 8

restore:
  method: "RSYNC"
  prefix: "user@host.domain.com:path/to/backups"
```

The definition of the `prefix` key is the same as *scp* so simply follow the [*scp*](#scpOption) instructions for determining the actual prefix and testing basic connectivity.

#### <a name="rcloneOption"> *rclone* (Dropbox) </a>

Selecting *rclone* unleashes the power of that package. However, this guide only covers setting up a Dropbox remote. For more information about *rclone*, see:

* [rclone.org](https://rclone.org)
* [Dropbox configuration guide](https://rclone.org/dropbox/).

You can install a template [configuration file](#configFile) for *rclone* like this:

```
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh RCLONE
``` 

The template is:

```
backup:
  method: "RCLONE"
  prefix: "remote:path/to/backups"
  retain: 8

restore:
  method: "RCLONE"
  prefix: "remote:path/to/backups"
```

Field definitions:

* `remote` is the **name** you define when you run `rclone config` in the next step. I recommend "dropbox" (all in lower case).
* `path/to/backups` is the path to the target directory on Dropbox where you want backups to be stored. It is relative to the top level of your Dropbox directory structure so it should **not** start with a "/". Remember that it is a [prefix](#keyPrefix) and that each Raspberry Pi will need its own sub-directory matching its HOSTNAME environment variable.

##### Connecting *rclone* to Dropbox

To synchronise directories on your Raspberry Pi with Dropbox, you need to authorise *rclone* to connect to your Dropbox account. The computer where you do this is called the "authorising computer". The *authorising computer* can be any system (Linux, Mac, PC) where:

* *rclone* is installed; **and**
* a web browser is available.

The *authorising computer* **can** be your Raspberry Pi, providing it meets those two requirements. To be clear, you can not do this step via *ssh*. The work must be done via VNC or an HDMI screen and keyboard.

If the *authorising computer* is another computer then it should be running the same (or reasonably close) version of *rclone* as your Raspberry Pi. You should check both systems with:

```
$ rclone version
```
	
and perform any necessary software updates before you begin.

###### on the *authorising computer*

1. Open a Terminal window and run the command:
	
	```
	$ rclone authorize "dropbox"
	```
		
2. *rclone* will do two things:

	- display the following message:
	
		```
		If your browser doesn't open automatically go to the following link:
		    http://127.0.0.1:nnnnn/auth?state=xxxxxxxx
		Log in and authorize rclone for access
		Waiting for code...
		```
		
	- attempt to open your default browser using URL in the above message. In fact, everything may happen so quickly that you might not actually see the message because it will be covered by the browser window. If, however, a browser window does not open:
		
		- copy the URL to the clipboard;
		- launch a web browser yourself; and
		- paste the URL into the web browser

		Note:
		
		* you can't paste that URL on another machine. Don't waste time trying to replace "127.0.0.1" with a domain name or IP address of another computer. It will not work!
	
3. The browser will take you to Dropbox. Follow the on-screen instructions. If all goes well, you will see a message saying "Success".

4. Close (or hide or minimise) the browser window so that you can see the Terminal window again.

5. Back in the Terminal window, *rclone* will display output similar to the following:
	
	```
	Paste the following into your remote machine --->
	{"access_token":"gIbBeRiSh","token_type":"bearer","refresh_token":"gIbBeRiSh","expiry":"timestamp"}
	<---End paste
	```
	
6. Copy the JSON string (everything from and including the "{" up to and including the "}" and save it somewhere. This string is your "Dropbox Token".

###### on the Raspberry Pi

1. Open a Terminal window and run the command:

	```
	$ rclone config
	```

2. Choose "n" for "New remote".
3. Give the remote the name "dropbox" (lower-case recommended). Press <kbd>return</kbd>.
4. Find "Dropbox" in the list of storage types. At the time of writing it was:

	```
	10 / Dropbox
	   \ "dropbox"
	```

	Respond to the `Storage>` prompt with the number associated with "Dropbox" ("10" in this example) and press <kbd>return</kbd>.

5. Respond to the `client_id>` prompt by pressing <kbd>return</kbd> (ie leave it empty).

6. Respond to the `client_secret>` prompt by pressing <kbd>return</kbd> (ie leave it empty).

7. Respond to the `Edit advanced config?` prompt by pressing <kbd>return</kbd> to accept the default "No" answer.
8. Respond to the `Use auto config?` prompt by typing "n" and pressing <kbd>return</kbd>.
9. *rclone* will display the following instructions and then wait for a response:
	
	```
	Execute the following on the machine with the web browser (same rclone version recommended):
	
		rclone authorize "dropbox"
	
	Then paste the result below:
	result>
	```
	
10. Paste your "Dropbox Token" (saved as the last step taken on your *authorising computer*) and press <kbd>return</kbd>.

11. Respond to the `Yes this is OK` prompt by pressing <kbd>return</kbd> to accept the default "y" answer.
12. Press <kbd>q</kbd> and <kbd>return</kbd> to "Quit config".
13. Check your work:

	```
	$ rclone listremotes
	```

	The expected answer is:
	
	```
	dropbox:
	```
	
	where "dropbox" is the name you gave to the remote.
	
##### about your Dropbox token

The Dropbox token is stored in the `rclone` configuration file at:

```
~/.config/rclone/rclone.conf
```

The token is tied to both `rclone` (the application) and your Dropbox account but it is not tied to a specific machine. You can copy the `rclone.conf` to other computers.
	
##### test your Dropbox connection

You should test connectivity like this:

1. Replace the right hand side of the following with your actual values and then execute the command:

	```
	$ PREFIX="dropbox:path/to/backups"
	```
	
	Notes:
	
	* the word "dropbox" is assumed to be the **name** you assigned to the remote when you ran `rclone config`. If you capitalised "Dropbox" or gave it another name like "MyDropboxAccount" then you will need to substitute accordingly. It is **case sensitive**!
	* the right hand side (after the colon) should not contain embedded spaces or other characters that are open to misinterpretation by `bash`.
	* `path/to/backups` is relative to top of your Dropbox structure in the cloud. You should not use absolute paths (ie starting with a "/").
	* Remember that `path/to/backups` will be treated as a [prefix](#keyPrefix) and each machine where you run `iotstack_backup` will append its HOSTNAME to the prefix as a sub-folder.

2. Test communication with Dropbox:

	```
	$ rclone ls "$PREFIX"
	```

	Unless the target folder is empty (a problem you can fix by making sure it has at least one file), you should see a list of the files in that folder on Dropbox. You can also replace `ls` with `lsd` to see a list of sub-directories in the target folder.
	
	If the command displays an error, you may need to check your work.

Once you are sure your working PREFIX is correct, copy the values to the [configuration file](#configFile).

#### <a name="mixnmatch"> mix and match </a>

Although the templates assume the same method will be used for both backup and restore, it does not have to be that way. For starters, while *rsync* uses *scp* to synchronise the `~/IOTstack/backups` folder with the remote host, *rsync* has no "selective reverse synchronisation" functionality that can be used during restore so `method: "RSYNC"` simply invokes `method: "SCP"` during restores.

*rclone* does have an inverse method (`copy`) so that is used to selectively copy the required backup files for a restore. They do, however, come down from Dropbox and that may not always be appropriate.

For example, suppose you configure your Raspberry Pi to backup direct to Dropbox using *rclone*. You do that in the knowledge that the backup files will also appear on your laptop when it is next connected to the Internet.

Now comes time to restore. You may wish to take advantage of the fact that your laptop is available, so you can mix and match like this:

```
backup:
  method: "RCLONE"
  prefix: "remote:path/to/backups"
  retain: 8

restore:
  method: "SCP"
  prefix: "user@host.domain.com:path/to/backups"
```

### <a name="configCheck"> Check your configuration </a>

You can use the following command to check your [configuration file](#configFile): 

```
$ show_iotstack_configuration
```

The script will:

* fail if the `niet` dependency is not installed.  
* warn you if it can't find the configuration file.
* report "Element not found" against a field if it can't find an expected key in the configuration file.
* return nothing (or a traceback) if the configuration file is malformed.

If this script returns sensible results that reflect what you have placed in the configuration file then you can be reasonably confident that the backup and restore scripts will behave in a way that implements your intention.

## <a name="backupSide"> The backup side of things </a>

There are three scripts:

* `iotstack_backup_general` – backs-up everything<sup>†</sup> except InfluxDB databases
* `iotstack_backup_influxdb` – backs-up InfluxDB databases
* `iotstack_backup` – a supervisory script which calls both of the above and handles copying of the results to another host via *scp*.

	† "everything" is a slightly loose term. See below.

In general, `iotstack_backup` is the script you should call.

> Acknowledgement: the backup scripts were based on [Graham Garner's backup script](https://github.com/gcgarner/IOTstack/blob/master/scripts/docker_backup.sh) as at 2019-11-17.

### <a name="iotstackBackupGeneral"> iotstack\_backup\_general </a>

Usage (two forms):

```
iotstack_backup_general path/to/general-backup.tar.gz
iotstack_backup_general path/to/backupdir runtag {general-backup.tar.gz}
```

* In the first form, the argument is an absolute or relative path to the backup file.
* In the second form, the path to the backup file is constructed like this:

	```
	path/to/backupdir/runtag.general-backup.tar.gz
	```

	with *general-backup.tar.gz* being replaced if you supply a third argument.

* The resulting `.tar.gz` file will contain:
	* All files matching the patterns:

		* `~/IOTstack/docker-compose.yml*`
		* `~/IOTstack/docker-compose-override.yml*`
		* `~/IOTstack/compose-override.yml*`

	* everything in `~/IOTstack/services`
	* everything in `~/IOTstack/volumes`, except:

		* `~/IOTstack/volumes/influxdb`
		* `~/IOTstack/volumes/mariadb`<sup>†</sup>
		* `~/IOTstack/volumes/nextcloud`
		* `~/IOTstack/volumes/pihole.restored `
		* `~/IOTstack/volumes/postgres`<sup>†</sup>

	† omitted because it is not copy-safe but there are, as yet, no scripts to backup these databases like there is for InfluxDB. If you run these and you want to take the risk, just remove the exclusion from the script.

The reason for implementing this as a standalone script is to make it easier to take snapshots and/or build your own backup strategy.

Example:

```
$ cd
$ mkdir my_special_backups
$ cd my_special_backups
$ iotstack_backup_general before_major_changes.tar.gz
```

### <a name="iotstackBackupInfluxdb"> iotstack\_backup\_influxdb </a>

Usage (two forms):

```
iotstack_backup_influxdb path/to/influx-backup.tar
iotstack_backup_influxdb path/to/backupdir runtag {influx-backup.tar}
```

* In the first form, the argument is an absolute or relative path to the backup file.
* In the second form, the path to the backup file is constructed like this:

	```
	path/to/backupdir/runtag.influx-backup.tar
	```

	with *influx-backup.tar* being replaced if you supply a third argument.
	
* The resulting `.tar` file will contain a portable snapshot of all InfluxDB databases as of the moment that the script started to run.

The reason for implementing this as a standalone script is to make it easier to take snapshots and/or build your own backup strategy.

Example:

```
$ cd
$ mkdir my_special_backups
$ cd my_special_backups
$ iotstack_backup_influxdb before_major_changes.tar
```

### <a name="iotstackBackup"> iotstack\_backup </a>

Usage:

```
iotstack_backup {runtag} {by_host_id}
```

* *runtag* is an _optional_ argument which defaults to syntax defined at [about *runtag*](#aboutRuntag) For example:

	```
	2020-09-19_1138.iot-hub
	```

* *by\_host\_dir* is an _optional_ argument which defaults to the value of the HOSTNAME environment variable.

> In general, you should run `iotstack_backup` without parameters. Be sure you know what you are doing before you start experimenting with parameters.

The script invokes `iotstack_backup_general` and `iotstack_backup_influxdb` (in that order) and leaves the results in `~/IOTstack/backups` along with a log file containing everything written to `stdout` and `stderr` as the script executed. Given the example *runtag* above, the resulting files would be:

```
~/IOTstack/backups/2020-09-19_1138.iot-hub.backup-log.txt
~/IOTstack/backups/2020-09-19_1138.iot-hub.general-backup.tar.gz
~/IOTstack/backups/2020-09-19_1138.iot-hub.influx-backup.tar
```

The files are copied to the remote host using the method you defined in the [configuration file](#configFile), and then `~/IOTstack/backups` is cleaned up to remove older backups.

## <a name="restoreSide"> The restore side of things </a>

There are three scripts which provide the inverse functionality of the backup scripts:

* `iotstack_restore_general ` – restores everything present in the general backup
* `iotstack_restore_influxdb ` – restores InfluxDB databases
* `iotstack_restore` – a general restore which calls both of the above

In general, `iotstack_restore` is the script you should call.

### <a name="iotstackRestoreGeneral"> iotstack\_restore\_general </a>

Usage (two forms):

```
iotstack_restore_general path/to/general-backup.tar.gz
iotstack_restore_general path/to/backupdir runtag {general-backup.tar.gz}
```

* In the first form, the argument is an absolute or relative path to the backup file.
* In the second form, the path to the backup file is constructed like this:

	```
	path/to/backupdir/runtag.general-backup.tar.gz
	```

	with *general-backup.tar.gz* being replaced if you supply a third argument.
	
* In both cases, *general-backup.tar.gz* (or whatever filename you supply)  is expected to be a file created by `iotstack_backup_general`. The result is undefined if this expectation is not satisfied.
* Running `iotstack_restore_general` will restore:

	* everything in `~/IOTstack/services`
	* everything in `~/IOTstack/volumes`, except:

		* `~/IOTstack/volumes/influxdb`
		* `~/IOTstack/volumes/mariadb`<sup>†</sup>
		* `~/IOTstack/volumes/nextcloud`
		* `~/IOTstack/volumes/pihole.restored `
		* `~/IOTstack/volumes/postgres`<sup>†</sup>

	* `~/IOTstack/docker-compose.yml` in some situations.

	† if you removed the matching exclusion from `iotstack_backup_general` then these directories will be restored in as-backed-up state.
	
The following files are given special handling:

* `docker-compose.yml`
* `docker-compose-override.yml`
* `compose-override.yml`

This is to cater for two distinct situations:

* On a bare-metal restore, `~/IOTstack` will not contain any `.yml` file(s) so anything in the backup will be restored.
* If a `.yml` is already present in `~/IOTstack` then it may be the same as the backup or contain customisations that should not be overwritten. The restore compares the file in `~/IOTstack` with the one in *path_to.tar.gz*:
	* If the two files compare the same then nothing happens.
	* If the two files do not compare the same, the `.yml` from *path_to.tar.gz* will be moved into `~/IOTstack` with a date-time suffix. If you want to use a `.yml` that has a date-time suffix, you have to rename it by hand.
* Note: `iotstack_backup_general` treats compose file names as *prefixes* and includes anything that matches those prefixes. For example:

	- `docker-compose.yml*`

	will match:
	
	- `docker-compose.yml.2021-05-02_1150`

	However, `iotstack_restore_general` does **not** restore any tagged compose files that are present in a backup. If you want them, you will have to unpack the backup yourself.

The reason for implementing the "general" restore as a standalone script is to make it easier to manage snapshots and/or build your own backup strategy.

Example:

```
$ cd ~/my_special_backups
$ iotstack_restore_general before_major_changes.tar.gz
```

### <a name="iotstackRestoreInfluxdb"> iotstack\_restore\_influxdb </a>

Usage (two forms):

```
iotstack_restore_influxdb path/to/influx-backup.tar
iotstack_restore_influxdb path/to/backupdir runtag {influx-backup.tar}
```

* In the first form, the argument is an absolute or relative path to the backup file.
* In the second form, the path to the backup file is constructed like this:

	```
	path/to/backupdir/runtag.influx-backup.tar
	```

	with *influx-backup.tar* being replaced if you supply a third argument.
	
* In both cases, *influx-backup.tar* (or whatever filename you supply)  is expected to be a file created by `iotstack_backup_influxdb`. The result is undefined if this expectation is not satisfied.
* Running `iotstack_restore_influxdb` will restore the contents of a portable influx backup. The operation is treated as a "full" restore and proceeds by:
	* ensuring the influxdb container is not running
	* erasing everything below `~/IOTstack/volumes/influxdb`
	* erasing everything in `~/IOTstack/backups/influxdb/db`
	* restoring the contents of *influx-backup.tar* to `~/IOTstack/backups/influxdb/db`
	* activating the `influxdb` container (which will re-initialise to "factory conditions")
	* instructing influx to restore the contents of `~/IOTstack/backups/influxdb/db`
	* terminating the `influxdb` container.

### <a name="iotstackRestore"> iotstack\_restore </a>

Usage:

```
iotstack_restore runtag {by_host_dir}
```

* *runtag* is a _required_ argument which must exactly match the *runtag* used by the `iotstack_backup` run you wish to restore. For example:

	```
	$ iotstack_restore 2020-09-19_1138.iot-hub
	```
	
* *by\_host\_dir* is an _optional_ argument. If omitted, the script assumes that *runtag* matches the syntax defined at [about *runtag*](#aboutRuntag) and treats all characters to the right of the first period as the *by\_host\_dir*. For example, given the *runtag*:

	```
	2020-09-19_1138.iot-hub
	```
	
	then *by\_host\_dir* will be:
	
	```
	iot-hub
	```
	
	If you pass a *runtag* which can't be parsed to extract the *by\_host\_dir* then you must also pass a valid *by\_host\_dir*.

The script:

* Creates a temporary directory within `~/IOTstack` (to ensure everything winds up on the same file-system)
* Uses your chosen method to copy files matching the pattern *runtag.\** into the temporary directory
* Deactivates your stack (if at least one container is running)
* Invokes `iotstack_restore_general`
* Invokes `iotstack_restore_influxdb`
* Cleans-up the temporary directory
* Reactivates your stack if it was deactivated by this script.

Both `iotstack_restore_general` and `iotstack_restore_influxdb` are invoked with two arguments:

* The path to the temporary restore directory; and
* The *runtag*.

Each script assumes that the path to its backup file can be derived from those two arguments. This will be true if the backup was created by `iotstack_backup` but is something to be aware of if you roll your own solution.

## <a name="bareMetalRestore"> Bare-metal restore </a>

Scenario. Your SD card wears out, or your Raspberry Pi emits magic smoke, or you decide the time has come for a fresh start:

1. Image a new SD card and/or build an SSD image.
2. Install all the dependencies (eg git, curl, wget, rsync, rclone, niet).
3. Clone the [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack) repository.

	```
	$ git clone -b old-menu https://github.com/SensorsIot/IOTstack.git ~/IOTstack
	```
 
	Note:
	
	* if you prefer "new menu" then omit the `-b old-menu`

4. Mimic how the menu installs Docker and Docker-Compose (the following is a superset of old- and new-menu):

	```	
	$ sudo bash -c '[ $(egrep -c "^allowinterfaces eth*,wlan*" /etc/dhcpcd.conf) -eq 0 ] && echo "allowinterfaces eth*,wlan*" >> /etc/dhcpcd.conf'
	$ curl -fsSL https://get.docker.com | sh
	$ sudo usermod -G docker -a $USER
	$ sudo usermod -G bluetooth -a $USER
	$ sudo apt install -y python3-pip python3-dev
	$ sudo pip3 install -U docker-compose
	$ sudo pip3 install -U ruamel.yaml==0.16.12 blessed
	```
	
5. Reboot.
6. Clone the [Paraphraser/IOTstackBackup](https://github.com/https://github.com/Paraphraser/IOTstackBackup) repository and install the scripts:

	```
	$ mkdir -p ~/.local
	$ cd ~/.local
	$ git clone https://github.com/Paraphraser/IOTstackBackup.git IOTstackBackup
	$ cd IOTstackBackup
	$ ./install_scripts.sh
	```

7. Either recover or recreate both:

	```
	~/.config/rclone/rclone.conf
	~/.config/iotstack_backup/config.yml
	```
	
8. Run `iotstack_restore` with the runtag of a recent backup. Among other things, this will recover `docker-compose.yml` (ie there is no need to run the menu and re-select your services).
9. Bring up the stack.

## <a name="iotstackReloadInfluxdb"> iotstack\_reload\_influxdb </a>

Usage:

```
iotstack_reload_influxdb
```

I wrote this script because I noticed a difference in behaviour between my "live" and "test" RPis. Executing this command:

```
$ docker exec -it influxdb bash
```

on the "live" RPi was extremely slow (30 seconds). On the "test" RPi, it was almost instantaneous. The hardware was indentical. The IOTstack installation identical, the Docker image versions for InfluxDB were identical. The only plausible explanation was that the InfluxDB databases on the "live" RPi had grown organically whereas the databases on the "test" RPi were routinely restored by `iotstack_restore`.

I wrote this script to test whether a reload on the "live" RPi would improve performance. The script:

* Instructs InfluxDB to backup the current databases
* Takes the stack down
* Removes `~/IOTSTACK/volumes/influxdb/data` and its contents
* Brings the stack up (at which point the InfluxDB databases will be empty)
* Instructs InfluxDB to restore from the databases from backup.

I had assumed that I would need to re-run this script periodically, whenever opening a shell got too slow for my needs. But the problem seems to have been a one-off. The databases on the "live" machine still grow organically but the *slowness* problem has not recurred.

See also:

* [about InfluxDB backup and restore commands](#aboutInfluxCommands)
* [about InfluxDB database restoration](#aboutInfluxRestore).

## <a name="endNotes"> Notes </a>

### <a name="aboutRuntag">about *runtag*</a>

When omitted as an argument to `iotstack_backup`, *runtag* defaults to the current date-time value in the format *yyyy-mm-dd_hhmm* followed by the host name as determined from the HOSTNAME environment variable. For example:

```
2020-09-19_1138.iot-hub
```

The *yyyy-mm-dd_hhmm.hostname* syntax is assumed by both `iotstack_backup` and `iotstack_restore` but no checking is done to enforce this.

If you pass a value for *runtag*, it must be a single string that does not contain characters that are open to misinterpretation by `bash`, such as spaces, dollar signs and so on.

There is also an implied assumption that HOSTNAME does not contain spaces or special characters.

The scripts will **not** protect you if you ignore this restriction. Ignoring this restriction **will** create a mess and you have been warned!

You are welcome to fix the scripts so that you can pass arbitrary quoted strings (eg "my backup from last tuesday") but those are **not** supported at the moment.

### <a name="aboutInfluxCommands">about InfluxDB backup and restore commands</a>

When you examine the scripts, you will see that `influxd` is instructed to perform a backup like this:

```
docker exec influxdb influxd backup -portable /var/lib/influxdb/backup
```

while a restore is handled like this:

```
docker exec influxdb influxd restore -portable /var/lib/influxdb/backup
```

In both cases, `/var/lib/influxdb/backup` is a path *inside* the container which maps to `~/IOTstack/backups/influxdb/db` *outside* the container. This mapping is defined in `~/IOTstack/docker-compose.yml`.

### <a name="aboutInfluxRestore">about InfluxDB database restoration</a>

InfluxDB database restoration produces a series of messages which fit these two basic patterns:

```
yyyy/mm/dd hh:mm:ss Restoring shard nnn live from backup yyyymmddThhmmssZ.snnn.tar.gz
yyyy/mm/dd hh:mm:ss Meta info not found for shard nnn on database _internal. Skipping shard file yyyymmddThhmmssZ.snnn.tar.gz
```

I have no idea what the "Meta info not found" messages actually mean. They sound ominous but they seem to be harmless. I have done a number of checks and have never encountered any data loss across a backup and restore. I think these messages can be ignored.

### <a name="usingcron">using cron to run iotstack\_backup </a>

I do it like this.

1. Scaffolding:

	```
	$ mkdir ~/Logs
	$ touch ~/Logs/iotstack_backup.log
	```
	
2. crontab preamble:

	```
	SHELL=/bin/bash
	HOME=/home/pi
	PATH=/home/pi/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	```
	
3. crontab entry:

	```
	# backup Docker containers and configurations once per day at 11:00am
	00	11	*	*	*	iotstack_backup >>./Logs/iotstack_backup.log 2>&1
	```
	
	See [crontab.guru](https://crontab.guru/#00_11_*_*_*) if you want to understand the syntax of the last line.
	
The completed `crontab` would look like this:

```
SHELL=/bin/bash
HOME=/home/pi
PATH=/home/pi/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# backup Docker containers and configurations once per day at 11:00am
00	11	*	*	*	iotstack_backup >>./Logs/iotstack_backup.log 2>&1
```

If you are unsure about how to set up a `crontab`:

1. First check whether you have an existing `crontab` by:

	```
	$ crontab -l
	```
	
	The command will either display your `crontab` or report:
	
	```
	no crontab for pi
	```

2. If you have an existing `crontab`, you can either:

	* Edit your `crontab` in-situ via this command:
	
		```
		$ crontab -e
		```
	
 		This will either use the value of your `EDITOR` environment variable (if you have set it) or offer choice of editors.
 		
 	* Prepare your `crontab` as a separate file (eg "my-crontab.txt") and import it:

		```
		$ crontab my-crontab.txt
		```
		
3. Combine the two methods. First, export your existing `crontab`:

	```
	$ crontab -l >my-crontab.txt
	```
	
	Edit the "my-crontab.txt" file, and finish by re-importing the edited file:
	
	```
	$ crontab my-crontab.txt
	```

If everything works as expected, `~/Logs/iotstack_backup.log` will be empty. The actual log is written to *yyyy-mm-dd_hhmm.backup-log.txt* inside `~/IOTstack/backups`.

When things don't go as expected (eg a permissions issue), the information you will need for debugging will turn up in `~/Logs/iotstack_backup.log` and you may also find a "You have new mail" message on your next login.

### <a name="periodicMaintenance"> periodic maintenance </a>

From time to time, you should synchronise your local copy of the IOTstackBackup repository by synchronising it with GitHub and then reinstall the scripts:

```
$ cd ~/.local/IOTstackBackup
$ git pull
$ ./install_scripts.sh
```
