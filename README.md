# IOTstack Backup and Restore

This project documents my approach to backup and restore of [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). My design goals were:

1. Live backup:

	* I see no sense in a backup strategy which only works when the stack is down.

2. Avoid the double-compression implicit in the scripts supplied with [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack):

	* An InfluxDB backup produces .tar.gz files. This is true for both InfluxDB&nbsp;1.8 and InfluxDB&nbsp;2. Simply collecting those into a separate .tar is more efficient than recompressing them into a .tar.gz.

3. Provide a variety of post-backup methods to copy backup files from a "live" Raspberry Pi to another machine on the local network and/or to the cloud. With appropriate choices, three levels of backup are possible:

	* Recent backups are stored on the Raspberry Pi in `~/IOTstack/backups/`
	* On-site copies are stored on another machine on the local network
	* Off-site copies are stored in the cloud (eg Dropbox).

4. More consistent and cron-friendly logging of whatever was written to `stdout` and `stderr` as the backup script ran.
6. Efficient restore of a backup, including a "bare-metal" restore:

	* When I first developed these scripts, there was no equivalent for [`iotstack_restore`](#iotstackRestore) in [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). That was a gap I wanted to rectify. 

These scripts will never be *guaranteed* to cover the full gamut of container types supported by [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). The main problem lies with containers where it is unsafe to copy the container's persistent storage while the container is running. This mainly applies to database engines. The support matrix is:

non-copy-safe container  | supported
-------------------------|:---------:
InfluxDB 1.8             | yes
InfluxDB 2               | yes
MariaDB                  | yes
Nextcloud + Nextcloud_DB | yes
Postgres                 | yes <sup>†</sup>
Subversion               | no

† 2023-Feb-08 Depends on:

1. [PR661](https://github.com/SensorsIot/IOTstack/pull/661) and [PR662](https://github.com/SensorsIot/IOTstack/pull/662) being merged into IOTstack (which was done on 2023-03-02); **and**
2. You updating your local copy of IOTstack (eg `git pull`); **and**
2. Adoption of the updated service definition for Postgres in your compose file.

## Contents

- [Setup](#setup)

	- [Download repository](#downloadRepository)
	- [Preparing for Nextcloud and MariaDB backups](#nextcloudMariaDBprep)
	- [Preparing for InfluxDB 2 backups](#influxDB2prep)
	- [Install dependencies](#installDependencies)
	- [The configuration file](#configFile)

		- [method:](#keyMethod)
		- [options:](#keyOptions)
		- [prefix:](#keyPrefix)
		- [retain:](#keyRetain)

	- [Choose your backup and restore methods](#chooseMethods)

		- [*scp*](#scpOption)
		- [*rsync*](#rsyncOption)
		- [*rclone* (Dropbox)](#rcloneOption)
		- [mix and match](#mixnmatch)

	- [Check your configuration](#configCheck)

- [Reference tables](#referenceTables)

	- [Table 1: assumed backup file extensions](#refExtensions)
	- [Table 2: default backup file names](#refFilenames)
	- [Table 3: associated containers](#refContainers)

- [The backup side of things](#backupSide)

	- [iotstack\_backup (umbrella script)](#iotstackBackup)
	- [iotstack\_backup\_general](#iotstackBackupGeneral)
	- [iotstack\_backup\_*«container»*](#iotstackBackupContainer)

- [The restore side of things](#restoreSide)

	- [iotstack\_restore (umbrella script)](#iotstackRestore)
	- [iotstack\_restore\_general](#iotstackRestoreGeneral)
	- [iotstack\_restore\_*«container»*](#iotstackRestoreContainer)

- [Bare-metal restore](#bareMetalRestore)
- [Environment variables](#envVars)
- [Reloading Influx databases "in situ"](#iotstackReloadInflux)
- [Notes](#endNotes)

	- [about «runtag»](#aboutRuntag)
	- [if Nextcloud gets stuck in "maintenance mode"](#nextcloudMaintenanceMode)
	- [using cron to run iotstack\_backup](#usingcron)

		- [understanding logging when cron is involved](#cronLogging)

	- [periodic maintenance](#periodicMaintenance)

- [Tutorials & Guides](#tutorials)

<a name="setup"></a>
## Setup

<a name="downloadRepository"></a>
### Download repository

This repository can be cloned anywhere on your Raspberry Pi but I recommend the `~/.local` directory:

```bash
$ mkdir -p ~/.local
$ cd ~/.local
$ git clone https://github.com/Paraphraser/IOTstackBackup.git IOTstackBackup
$ cd IOTstackBackup
$ ./install_scripts.sh
```

Notes:

* If `~/.local/bin` already exists, the scripts are copied into it.
* If `~/.local/bin` does not exist, the Unix PATH is searched for an alternative directory that is under your home directory. If the search:

	- *succeeds*, the scripts are copied into that directory
	- *fails*, `~/.local/bin` is created and the scripts are copied into it.

Check the result by executing:

```bash
$ which iotstack_backup
```

You will either see a path like:

```bash
/home/pi/.local/bin/iotstack_backup
```

or get "silence". If `which` does not return a path, try logging-out and in again to give your `~/.profile` or `~/.bashrc` the chance to add `~/.local/bin` to your search path, and then repeat the test.

> There are many reasons why a folder like `~/.local/bin` might not be in your search path. It is beyond the scope of this document to explore all the possibilities. Google is your friend.

<a name="nextcloudMariaDBprep"></a>
### Preparing for Nextcloud and MariaDB backups

Nextcloud backup and restore was introduced in September 2021; MariaDB in May 2022. Both have several dependencies on IOTstack which you should check before your first backup run.

1. Make sure your local copy of the IOTstack repository is fully up-to-date:

	* If you normally run new menu (master branch):

		```bash
		$ cd ~/IOTstack
		$ git checkout master
		$ git pull
		```

	* If you normally run old menu (old-menu branch):

		```bash
		$ cd ~/IOTstack
		$ git checkout old-menu
		$ git pull
		```

2. List the reference service definitions:

	* Nextcloud

		```bash
		$ cat ~/IOTstack/.templates/nextcloud/service.yml
		```

		At the time of writing, the new menu version it looked like this:

		```yaml
		nextcloud:
		  container_name: nextcloud
		  image: nextcloud
		  restart: unless-stopped
		  environment:
		    - MYSQL_HOST=nextcloud_db
		    - MYSQL_PASSWORD=%randomMySqlPassword%
		    - MYSQL_DATABASE=nextcloud
		    - MYSQL_USER=nextcloud
		  ports:
		    - "9321:80"
		  volumes:
		    - ./volumes/nextcloud/html:/var/www/html
		  depends_on:
		    - nextcloud_db
		  networks:
		    - default
		    - nextcloud

		nextcloud_db:
		  container_name: nextcloud_db
		  build: ./.templates/mariadb/.
		  restart: unless-stopped
		  environment:
		    - TZ=Etc/UTC
		    - PUID=1000
		    - PGID=1000
		    - MYSQL_ROOT_PASSWORD=%randomPassword%
		    - MYSQL_PASSWORD=%randomMySqlPassword%
		    - MYSQL_DATABASE=nextcloud
		    - MYSQL_USER=nextcloud
		  volumes:
		    - ./volumes/nextcloud/db:/config
		    - ./volumes/nextcloud/db_backup:/backup
		  networks:
		    - nextcloud
		```

		The old-menu version is similar, save that it uses fixed passwords instead of "%" delimited placeholders.

	* MariaDB

		```bash
		$ cat ~/IOTstack/.templates/mariadb/service.yml
		```

		At the time of writing, the new menu version it looked like this:

		```yaml
		mariadb:
		  build: ./.templates/mariadb/.
		  container_name: mariadb
		  environment:
		    - TZ=Etc/UTC
		    - PUID=1000
		    - PGID=1000
		    - MYSQL_ROOT_PASSWORD=%randomAdminPassword%
		    - MYSQL_DATABASE=default
		    - MYSQL_USER=mariadbuser
		    - MYSQL_PASSWORD=%randomPassword%
		  volumes:
		    - ./volumes/mariadb/config:/config
		    - ./volumes/mariadb/db_backup:/backup
		  ports:
		    - "3306:3306"
		  restart: unless-stopped
		```

		The old-menu version is similar, save that the environment variables are stored in a separate file.

3. Compare and contrast the reference service definitions above with those in your compose file and make appropriate adjustments. In general, you should adopt the reference versions and add your own environment variables.

4. Start the container(s) and run the following commands:

	* Nextcloud

		```bash
		$ docker ps --format "table {{.Names}}\t{{.RunningFor}}\t{{.Status}}" --filter name=nextcloud_db
		```

		The expected output is:

		```
		NAMES          CREATED         STATUS
		nextcloud_db   «time period»   Up «time period» (healthy)
		```

	* MariaDB

		```bash
		$ docker ps --format "table {{.Names}}\t{{.RunningFor}}\t{{.Status}}" --filter name=mariadb
		```

		The expected output is:

		```
		NAMES          CREATED         STATUS
		mariadb        «time period»   Up «time period» (healthy)
		```

	Notice the "healthy" annotation. If the container has only just started, you might also see "(health: starting)". Both of those are indications that a "health check" process is running inside the container.

	The IOTstackBackup scripts depend on the availability of the health check process.

	The health check process for MariaDB containers was added to IOTstack on 2021-10-17. If you do **not** see evidence that your containers are running their health checks, you probably need to rebuild either or both, like this:

	```bash
	$ cd ~/IOTstack
	$ docker-compose build --no-cache --pull «container»
	$ docker-compose up -d «container»
	```

	where:

	* *«container»* is either `nextcloud_db` or `mariadb`.

	Note:

	* This assumes you did Step 1 (the `git pull` to bring your local copy of the IOTstack repository is fully up-to-date).

<a name="influxDB2prep"></a>
### Preparing for InfluxDB 2 backups

InfluxDB&nbsp;2 support was added to IOTstackBackup in May 2022. See also:

* [IOTstack Wiki - InfluxDB 2](https://sensorsiot.github.io/IOTstack/Containers/InfluxDB2/)
* [InfluxDB 2 experiments](https://gist.github.com/Paraphraser/aef2dbcc37f8f895ec7ead1068fd8bf1) (gist).

<a name="installDependencies"></a>
### Install dependencies

Make sure your system satisfies the following dependencies:

```bash
$ sudo apt install -y rsync python3-pip python3-dev curl jq wget
$ curl https://rclone.org/install.sh | sudo bash
$ sudo pip3 install -U shyaml
```

Some (or all) may be installed already on your Raspberry Pi. Some things to note:

1. You can also install *rclone* via `sudo apt install -y rclone` but you get an obsolete version. It is better to use the method shown here.
2. *shyaml* is a YAML parser (analogous to *jq* for JSON files).
3. If you prefer, you can omit the `sudo` when installing `shyaml`. *With* `sudo`, the tool is installed globally; *without,* it is installed for the current user.

<a name="configFile"></a>
### The configuration file

The [`iotstack_backup`](#iotstackBackup) and [`iotstack_restore`](#iotstackRestore) scripts depend on a configuration file at the path:

```
~/.config/iotstack_backup/config.yml
```

A script is provided to initialise a template configuration but you will need to edit the file by hand once you choose your backup and restore methods. The configuration file follows the normal YAML syntax rules. In particular, you must use spaces for indentation. You must not use tabs.

<a name="keyMethod"></a>
#### method:

What "method" means depends on your perspective. For **backup** operations you have a choice of:

* SCP (file-level copying)
* RSYNC (folder-level synchronisation)
* RCLONE (folder-level synchronisation)

For **restore** operations, your choices are:

* SCP (file-level copying)
* <a name="rsyncUsesScp"></a>RSYNC (file-level copying; actually uses *scp*)
* RCLONE (file-level copying)

Although the templates assume you will use the same method for both backup and restore, this is not a requirement. You are free to [mix and match](#mixnmatch).

<a name="keyOptions"></a>
#### options:

Caution:

* This is an **experimental** field. Use it at your own risk.

The "options" field is designed to address a specific problem with the SCP method.

The `scp` command is in transition from supporting the *secure copy protocol* (SCP) to supporting the *secure file transfer protocol* (SFTP). In theory, the client and server will negotiate whether they both support SFTP and will fall back to SCP as the lowest common denominator. However, there can be situations where the client and server both believe SFTP is available yet, for some reason, the client sends a command which the server is unable to implement, or vice versa.

This problem can be overcome by passing the `-O` flag to the `scp` command. This flag forces the use of SCP, irrespective of whether SFTP is available.

The configuration file templates provided with IOTstackBackup include the following clause where its use *may* be relevant:

```
  # options: "-O"
```

The situations where it *may* be relevant are:

1. Where SCP is either the backup or restore method; and
2. Where RSYNC is the restore method. This is because RSYNC restore is [implemented by calling SCP](#rsyncUsesScp).

The reason why the clause is commented-out by default is because the `-O` flag is only available on `scp` commands (clients) which support both SCP and SFTP. In other words, if `-O` is passed to an `scp` command which does not support the option, the command aborts. 

To enable the `-O` flag, remove the leading `# ` from the configuration file. Active `options:` clauses will show up when you [check your configuration file](#configCheck).

Although the `options:` clause was implemented to address the specific problem with SCP, it is actually supported for **all** methods. Any value you provide will be passed to your chosen backup and/or restore method. No checking is done and you are entirely responsible for ensuring that you only pass options to your chosen method which are both valid and make sense in context. That is why its use is "at your own risk".

<a name="keyPrefix"></a>
#### prefix:

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

Both of those are *prefixes*. When [`iotstack_backup`](#iotstackBackup) runs, it appends the HOSTNAME environment variable to the prefix to form the path to the actual backup directory. For example, suppose the Raspberry Pi has the name `iot-hub`. Appending the host name to the two example prefixes above results in:

```
user@host.domain.com:IOTstackBackups/iot-hub
dropbox:MyIOTstackBackups/iot-hub
```

The `iot-hub` directory on the remote system is where the backups from the host named `iot-hub` will be stored.

In other words, the hostname is used as a *discriminator*. If you have more than one Raspberry Pi, you can safely use the same [configuration file](#configFile) on each Raspberry Pi without there being any risk of your backups becoming co-mingled or otherwise leading to confusion.

The [`iotstack_restore`](#iotstackRestore) command has complementary logic. It can either derive the hostname from the [«runtag»](#aboutRuntag) or you can pass the correct value as a parameter.

Notes:

* Both the path portion of the prefix (eg `IOTstackBackups`) and all per-machine subdirectories (eg `iot-hub`) should exist on the remote machine **before** you run [`iotstack_backup`](#iotstackBackup) for the first time on any Raspberry Pi.
* The *rclone* method *will* automatically create missing directories on the remote host but the *scp* and *rsync* methods will **not**. You have to create the directories by hand.

<a name="keyRetain"></a>
#### retain:

The `retain` keyword is an instruction to the backup script as to how many previous backups it should retain *on the Raspberry Pi*.

This, in turn, will *influence* the number of backups retained on the remote host if you choose either the *rclone* or *rsync* options.

To repeat:

* `retain` only controls what is retained on the Raspberry Pi. What happens on remote hosts depends on the `method` you choose in the next step.

<a name="chooseMethods"></a>
### Choose your backup and restore methods

<a name="scpOption"></a>
#### *scp*

*scp* (secure copy) saves the results of *this* backup run. Backup files copied to the remote will be retained on the remote until *you* take some action to remove them.

You can install a template [configuration file](#configFile) for *scp* like this:

```bash
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh SCP
``` 

The template is:

```yaml
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

	```bash
	$ PREFIX="user@host.domain.com:path/to/backups"
	```

	Notes:

	* The right hand side should not contain embedded spaces or other characters that are open to misinterpretation by `bash`.
	* `path/to/backups` is assumed to be relative to the home directory of `user` on the remote machine. You *can* use absolute paths (ie starting with a "/") if you wish.
	* all directories in the path defined by `path/to/backups` must exist and be writeable by `user`.

2. Test sending from this host to the remote host:

	```bash
	$ touch test.txt
	$ scp test.txt "$PREFIX/test.txt"
	$ rm test.txt
	```

3. Test fetching from the remote host to this host:

	```bash
	$ scp "$PREFIX/test.txt" ./test.txt
	$ rm test.txt
	```

Your goal is that both of the *scp* commands should work without prompting for passwords or the need to accept fingerprints. Follow [this tutorial](ssh-tutorial.md) if you don't know how to do that.

Once you are sure your working PREFIX is correct, use your favourite text editor to copy the values to the [configuration file](#configFile).

<a name="rsyncOption"></a>
#### *rsync*

*rsync* uses *scp* but performs more work. The essential difference between the two methods is what happens during the final stages of a backup:

* *scp* copies the individual **files** produced by *that* backup to the remote machine; while
* *rsync* synchronises the `~/IOStack/backups` **directory** on the Raspberry Pi with the backup directory on the remote machine.

The `~/IOStack/backups` directory is trimmed at the end of each backup run. The trimming occurs **after** *rsync* runs so, in practice the backup directory on the remote machine will usually have one more backup than the Raspberry Pi.

You can install a template [configuration file](#configFile) for *rsync* like this:

```bash
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh RSYNC
``` 

The template is:

```yaml
backup:
  method: "RSYNC"
  prefix: "user@host.domain.com:path/to/backups"
  retain: 8

restore:
  method: "RSYNC"
  prefix: "user@host.domain.com:path/to/backups"
```

The definition of the `prefix` key is the same as *scp* so simply follow the [*scp*](#scpOption) instructions for determining the actual prefix and testing basic connectivity.

<a name="rcloneOption"></a>
#### *rclone* (Dropbox)

Selecting *rclone* unleashes the power of that package. However, this guide only covers setting up a Dropbox remote. For more information about *rclone*, see:

* [rclone.org](https://rclone.org)
* [Dropbox configuration guide](https://rclone.org/dropbox/).

You can install a template [configuration file](#configFile) for *rclone* like this:

```bash
$ cd ~/.local/IOTstackBackup/configuration-templates
$ ./install_template.sh RCLONE
``` 

The template is:

```yaml
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

```bash
$ rclone version
```

and perform any necessary software updates before you begin.

###### on the *authorising computer*

1. Open a Terminal window and run the command:

	```bash
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

	- attempt to open your default browser using the URL in the above message. In fact, everything may happen so quickly that you might not actually see the message because it will be covered by the browser window. If, however, a browser window does not open:

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

	```bash
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

	```bash
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

	```bash
	$ PREFIX="dropbox:path/to/backups"
	```

	Notes:

	* the word "dropbox" is assumed to be the **name** you assigned to the remote when you ran `rclone config`. If you capitalised "Dropbox" or gave it another name like "MyDropboxAccount" then you will need to substitute accordingly. It is **case sensitive**!
	* the right hand side (after the colon) should not contain embedded spaces or other characters that are open to misinterpretation by `bash`.
	* `path/to/backups` is relative to top of your Dropbox structure in the cloud. You should not use absolute paths (ie starting with a "/").
	* Remember that `path/to/backups` will be treated as a [prefix](#keyPrefix). Each machine where you run [`iotstack_backup`](#iotstackBackup) will append its HOSTNAME to the prefix as a sub-folder.

2. Test communication with Dropbox:

	```bash
	$ rclone ls "$PREFIX"
	```

	Unless the target folder is empty (a problem you can fix by making sure it has at least one file), you should see a list of the files in that folder on Dropbox. You can also replace `ls` with `lsd` to see a list of sub-directories in the target folder.

	If the command displays an error, you may need to check your work.

Once you are sure your working PREFIX is correct, use your favourite text editor to copy the values to the [configuration file](#configFile).

<a name="mixnmatch"></a>
#### mix and match

Although the templates assume the same method will be used for both backup and restore, it does not have to be that way. For starters, while *rsync* uses *scp* to synchronise the `~/IOTstack/backups` folder with the remote host, *rsync* has no "selective reverse synchronisation" functionality that can be used during restore so `method: "RSYNC"` simply invokes `method: "SCP"` during restores.

*rclone* does have an inverse method (`copy`) so that is used to selectively copy the required backup files for a restore. They do, however, come down from Dropbox and that may not always be appropriate.

For example, suppose you configure your Raspberry Pi to backup direct to Dropbox using *rclone*. You do that in the knowledge that the backup files will also appear on your laptop when it is next connected to the Internet.

Now comes time to restore. You may wish to take advantage of the fact that your laptop is available, so you can mix and match like this:

```yaml
backup:
  method: "RCLONE"
  prefix: "remote:path/to/backups"
  retain: 8

restore:
  method: "SCP"
  prefix: "user@host.domain.com:path/to/backups"
```

<a name="configCheck"></a>
### Check your configuration

You can use the following command to check your [configuration file](#configFile): 

```bash
$ show_iotstackbackup_configuration
```

The script will:

* fail if the `shyaml` dependency is not installed.  
* warn you if it can't find the configuration file.
* report "Element not found" against a field if it can't find an expected key in the configuration file.
* return nothing (or a traceback) if the configuration file is malformed.

If this script returns sensible results that reflect what you have placed in the configuration file then you can be reasonably confident that the backup and restore scripts will behave in a way that implements your intention.

<a name="configChecking"></a>
#### if you get a traceback …

`show_iotstackbackup_configuration` uses the `shyaml` package to extract information from your [configuration file](#configFile). In turn, `shyaml` calls a YAML parsing API to scan your [configuration file](#configFile) and turn it into structures that can be interpreted by `shyaml`.

If the YAML API encounters a fundamental problem in your [configuration file](#configFile), it will cause `shyaml` to abort with a traceback.

Because `show_iotstackbackup_configuration` calls `shyaml` five times, you may get as many as five tracebacks and the sheer volume of output may seem overwhelming. However, you can ignore most of it. Just look for lines similar to the following:

```
yaml.scaller.ScannerError: while parsing …
  in "<stdin>", line «x», column «y»
```

That is telling you where the problem is. Here is a checklist of common problems with YAML files:

1. Using <kbd>tab</kbd> characters for indentation. You **must** use <kbd>space</kbd> characters.
2. Using “curly quotes” instead of "straight quotes" when encapsulating string values. This can happen if you use a general purpose text editor that has its own "curly quotes" setting or respects an equivalent operating-system level setting. You must use straight quotes.
3. Using a Windows-based text editor which appends 0x0D0A (CR+LF) line-endings rather than Unix-standard 0x0A (LF) line-endings.

<a name="referenceTables"></a>
## Reference tables

<a name="refExtensions"></a>
### Table 1: assumed backup file extensions

«script»                    | «extensions»
:--------------------------:|:------------------------:
`iotstack_backup_general`   | `.tar.gz`
`iotstack_backup_influxdb`  | `.tar`
`iotstack_backup_influxdb2` | `.tar`
`iotstack_backup_mariadb`   | `.tar.gz`
`iotstack_backup_nextcloud` | `.tar.gz`

Each extension implies the file's internal format. Violating this convention leads to a mess.

<a name="refFilenames"></a>
### Table 2: default backup file names

«script»                    | «defaultFileName»
:--------------------------:|:------------------------:
`iotstack_backup_general`   | `general-backup.tar.gz `
`iotstack_backup_influxdb`  | `influx-backup.tar` <sup>†</sup>
`iotstack_backup_influxdb2` | `influxdb2-backup.tar`
`iotstack_backup_mariadb`   | `mariadb-backup.tar.gz`
`iotstack_backup_nextcloud` | `nextcloud-backup.tar.gz`

† The default file name for InfluxDB&nbsp;1.8 is an exception. It would be more consistent to use `influxdb-backup.tar` but maintaining backwards compatibility demands `influx-backup.tar`.

<a name="refContainers"></a>
### Table 3: associated containers

«script»                    | associated container(s)
:--------------------------:|:------------------------:
`iotstack_backup_influxdb`  | `influxdb`
`iotstack_backup_influxdb2` | `influxdb2`
`iotstack_backup_mariadb`   | `mariadb`
`iotstack_backup_nextcloud` | `nextcloud` + `nextcloud_db`

<a name="backupSide"></a>
## The backup side of things

The backup side of things comprises a number of scripts with the prefix `iotstack_backup_` that are invoked by an umbrella script named `iotstack_backup`, which also handles copying of the backup files to another host.

In general, [`iotstack_backup`](#iotstackBackup) is the script you should call.

> Acknowledgement: the backup scripts were based on [Graham Garner's backup script](https://github.com/gcgarner/IOTstack/blob/master/scripts/docker_backup.sh) as at 2019-11-17.

<a name="iotstackBackup"></a>
### iotstack\_backup (umbrella script)

Usage:

```bash
$ iotstack_backup {«runtag»} {by_host_id}
```

* «runtag» is an _optional_ argument which defaults to syntax defined at [about «runtag»](#aboutRuntag) For example:

	```
	2022-05-24_1138.iot-hub
	```

* *by\_host\_dir* is an _optional_ argument which defaults to the value of the HOSTNAME environment variable.

In general, you should run `iotstack_backup` without parameters. If you decide to use parameters, please make sure you test thoroughly before you rely on the result in a production system.

The script invokes:

* [`iotstack_backup_general`](#iotstackBackupGeneral)
* [`iotstack_backup_influxdb`](#iotstackBackupContainer)
* [`iotstack_backup_influxdb2`](#iotstackBackupContainer)
* [`iotstack_backup_nextcloud`](#iotstackBackupContainer)
* [`iotstack_backup_mariadb`](#iotstackBackupContainer)
* [`iotstack_backup_postgres`](#iotstackBackupContainer)

The results of those are placed in `~/IOTstack/backups` along with a log file containing everything written to `stdout` and `stderr` as the script executed.

The files are copied to the remote host using the method you defined in the [configuration file](#configFile), and then `~/IOTstack/backups` is cleaned up to remove older backups.

<a name="iotstackBackupGeneral"></a>
### iotstack\_backup\_general

Usage (three forms):

1. Single-argument form:

	```bash
	$ iotstack_backup_general path/to/backupFile.tar.gz
	```

	The argument is an absolute or relative path to the backup file. The script assumes, but does not enforce, the file-type extensions of `.tar.gz`. The results are undefined if you use different extensions. 

	The main reason for supporting the single-argument form is to make it easy for you to take snapshots and/or build your own backup and restore strategy. For example:

	Example:

	```bash
	$ cd
	$ mkdir my_special_backups
	$ cd my_special_backups
	$ iotstack_backup_general before_major_changes.tar.gz
	```

2. Two-argument form:

	```bash
	$ iotstack_backup_general path/to/backupdir «runtag»
	```

	The first argument is a path (absolute or relative) to the folder where the backup file is to be stored. The second argument is the [«runtag»](#aboutRuntag). The path to the backup file is formed via concatenation:

	```
	path/to/backupdir/«runtag».general-backup.tar.gz
	``` 

	This form of the script is invoked by the [`iotstack_backup`](#iotstackBackup) umbrella script.

3. Three-argument form:

	```bash
	$ iotstack_backup_general path/to/backupdir «runtag» filename
	```

	This is effectively a blend of the first two forms. The path to the backup file is constructed by concatenation using the filename you supply instead of a default:

	```
	path/to/backupdir/«runtag».filename
	```

	If you use this form, remember to observe the script's assumption about the file-type extensions of `.tar.gz`.

Providing only that it can identify a viable IOTstack installation, this script always produces a backup file containing:

* All files matching the patterns:

	* `~/IOTstack/*.yml`
	* `~/IOTstack/*.env`

* The following file (if it exists):

	* `~/IOTstack/.env`

* everything in `~/IOTstack/services`
* everything in `~/IOTstack/volumes`, except:

	* `influxdb`
	* `influxdb2`
	* `mariadb`
	* `nextcloud`
	* `postgres` <sup>†</sup>
	* `subversion` <sup>†</sup>
	* `pihole.restored`
	* `lost+found`

	† omitted because the container is not copy-safe but, as yet, there is no container-specific backup script. If you run either container and want to take the risk, just remove the exclusion from the script.

<a name="iotstackBackupContainer"></a>
### iotstack\_backup\_*«container»*

Usage (three forms):

1. Single-argument form:

	```bash
	$ «script» path/to/backupFile
	```

	The argument is an absolute or relative path to the backup file. Each script assumes that the path to the backup file ends with the file-type extension shown in [Table 1](#refExtensions). The scripts do not enforce this. The results are undefined if you do not supply the correct extensions. 

	The main reason for supporting the single-argument form is to make it easy for you to take snapshots and/or build your own backup and restore strategy. For example:

	Example:

	```bash
	$ cd
	$ mkdir my_special_backups
	$ cd my_special_backups
	$ iotstack_backup_influxdb before_major_changes.tar
	```

2. Two-argument form:

	```bash
	$ «script» path/to/backupdir «runtag»
	```

	The first argument is a path (absolute or relative) to the folder where the backup file is to be stored. The second argument is the [«runtag»](#aboutRuntag). The path to the backup file is formed via concatenation:

	```
	path/to/backupdir/«runtag».«defaultFileName»
	``` 

	where «defaultFileName» comes from [Table 2](#refFilenames).

	This form of the script is invoked by the [`iotstack_backup`](#iotstackBackup) umbrella script.

3. Three-argument form:

	```bash
	$ «script» path/to/backupdir «runtag» filename
	```

	This is effectively a blend of the first two forms. The path to the backup file is constructed by concatenation using the filename you supply instead of a default:

	```
	path/to/backupdir/«runtag».filename
	```

	If you use this form, remember to observe each script's assumption about the correct file-type «extensions» ([Table 1](#refExtensions)).

Each script starts by checking the status of its associated container(s). See [Table 3](#refContainers). The associated container(s) must be running when the script starts and the script exits without creating a backup if this precondition is not met.

This is mainly because the database engines participate in the backup process so they must be running.

The [`iotstack_backup`](#iotstackBackup) umbrella script also relies on this behaviour. It calls all the subordinate scripts unconditionally, irrespective of whether the associated containers are even mentioned in your compose file. If and only if the database engine is running is it backed-up.

<a name="restoreSide"></a>
## The restore side of things

The restore side of things comprises a number of scripts with the prefix `iotstack_restore_` that are invoked by an umbrella script named `iotstack_restore`, which also handles fetching of backup files from another host.

In general, [`iotstack_restore`](#iotstackRestore) is the script you should call.

<a name="iotstackRestore"></a>
### iotstack\_restore (umbrella script)

Usage:

```bash
$ iotstack_restore «runtag» {«by_host_dir»}
```

* [«runtag»](#aboutRuntag) is a _required_ argument which must exactly match the «runtag» used by the [`iotstack_backup`](#iotstackBackup) run you wish to restore. For example:

	```bash
	$ iotstack_restore 2022-05-24_1138.iot-hub
	```

* «by\_host\_dir» is an _optional_ argument. If omitted, the script assumes that «runtag» matches the syntax defined at [about «runtag»](#aboutRuntag) and treats all characters to the right of the first period as the «by\_host\_dir». For example, given the «runtag»:

	```
	2022-05-24_1138.iot-hub
	```

	then «by\_host\_dir» will be:

	```
	iot-hub
	```

	If you pass a [«runtag»](#aboutRuntag) which can't be parsed to extract the «by\_host\_dir» then you must also pass a valid «by\_host\_dir».

The script:

* Creates a temporary directory within `~/IOTstack` (to ensure everything winds up on the same file-system)
* Uses your chosen method to copy files matching the pattern `«runtag».*` into the temporary directory
* Deactivates your stack (if at least one container is running)
* Invokes [`iotstack_restore_general`](#iotstackRestoreGeneral)
* Invokes [`iotstack_restore_influxdb`](#iotstackRestoreContainer)
* Invokes [`iotstack_restore_influxdb2`](#iotstackRestoreContainer)
* Invokes [`iotstack_restore_nextcloud`](#iotstackRestoreContainer)
* Invokes [`iotstack_restore_mariadb`](#iotstackRestoreContainer)
* Invokes [`iotstack_restore_postgres`](#iotstackRestoreContainer)
* Cleans-up the temporary directory
* Reactivates your stack if it was deactivated by this script.

The subordinate `iotstack_restore_general` and `iotstack_restore_«container»` scripts are invoked with two arguments:

* The path to the temporary restore directory; and
* The [«runtag»](#aboutRuntag).

Each script assumes that the path to its backup file can be derived from those two arguments. This will be true if the backup was created by [`iotstack_backup`](#iotstackBackup) but is something to be aware of if you roll your own solution.

<a name="iotstackRestoreGeneral"></a>
### iotstack\_restore\_general

Usage (three forms):

1. Single-argument form:

	```bash
	$ iotstack_restore_general path/to/backupFile.tar.gz
	```

	The argument is an absolute or relative path to the backup file. The script assumes, but does not enforce, the file-type extensions of `.tar.gz`. The results are undefined if you use different extensions. 

	The main reason for supporting the single-argument form is to make it easy for you to take snapshots and/or build your own backup and restore strategy. For example:

	Example:

	```bash
	$ cd ~/my_special_backups
	$ iotstack_restore_general before_major_changes.tar.gz
	```

2. Two-argument form:

	```bash
	$ iotstack_restore_general path/to/backupdir «runtag»
	```

	The first argument is a path (absolute or relative) to the folder where the backup file is to be stored. The second argument is the [«runtag»](#aboutRuntag). The path to the backup file is formed via concatenation:

	```
	path/to/backupdir/«runtag».general-backup.tar.gz
	``` 

	This form of the script is invoked by the [`iotstack_restore`](#iotstackRestore) umbrella script.

3. Three-argument form:

	```bash
	$ iotstack_restore_general path/to/backupdir «runtag» filename
	```

	This is effectively a blend of the first two forms. The path to the backup file is constructed by concatenation using the filename you supply instead of a default:

	```
	path/to/backupdir/«runtag».filename
	```

	If you use this form, remember to observe the script's assumption about the file-type extensions of `.tar.gz`.

If any IOTstack containers are running, the script exits without performing any restore operations. Otherwise, the script assumes the supplied backup file was created by `iotstack_backup_general`. The result is undefined if this assumption is not satisfied.

Running `iotstack_restore_general` will restore:

* everything in `~/IOTstack/services`
* everything in `~/IOTstack/volumes`, except:

	* `influxdb`
	* `influxdb2`
	* `mariadb`
	* `nextcloud`
	* `postgres`
	* `subversion`
	* `pihole.restored`
	* `lost+found`

Restoration of the **contents** of `./services` and `./volumes` occurs item-by-item according to the following decision table:

item in backup | item in ~/IOTstack | action
:-------------:|:------------------:|:-----------
no             | *irrelevant*       | none 
yes            | no                 | restore 
yes            | yes                | replace 

After that, any **files** remaining in the restore are given special handling. These typically include:

* any files with a `.yml` extension such as:

	* `docker-compose.yml`
	* `docker-compose-override.yml`
	* `compose-override.yml`

* `.env` and/or any files with a `.env` extension.

The decision table for these files is:

item in backup | item in ~/IOTstack | test              | action
:-------------:|:------------------:|:------------------|:-----------
no             | *irrelevant*       | *irrelevant*      | none 
yes            | no                 | none              | restore 
yes            | yes                | compare same      | none 
yes            | yes                | compare different | copy-with-suffix 

This is to cater for two distinct situations:

* On a bare-metal restore, `~/IOTstack` will not contain any of these files so everything in the backup will be restored "as is".
* If a file is already present in `~/IOTstack` then it may be the same as the backup or contain customisations that should not be overwritten. If the two files compare different, the file from the backup is restored with a date-time suffix. If you want to use a file that has a date-time suffix, you have to rename it by hand.

<a name="iotstackRestoreContainer"></a>
### iotstack\_restore\_*«container»*

Usage (three forms):

1. Single-argument form:

	```bash
	$ «script» path/to/backupFile
	```

	The argument is an absolute or relative path to the backup file. Each script assumes that the path to the backup file ends with the file-type extension shown in [Table 1](#refExtensions). The scripts do not enforce this. The results are undefined if you do not supply a backup file in the expected format.

	The main reason for supporting the single-argument form is to make it easy for you to take snapshots and/or build your own backup and restore strategy. For example:

	Example:

	```bash
	$ cd ~/my_special_backups
	$ iotstack_restore_influxdb before_major_changes.tar
	```

2. Two-argument form:

	```bash
	$ «script» path/to/backupdir «runtag»
	```

	The first argument is a path (absolute or relative) to the folder where the backup file is to be stored. The second argument is the [«runtag»](#aboutRuntag). The path to the backup file is formed via concatenation:

	```
	path/to/backupdir/«runtag».«defaultFileName»
	``` 

	where «defaultFileName» comes from [Table 2](#refFilenames).

	This form of the script is invoked by the [`iotstack_restore`](#iotstackRestore) umbrella script.

3. Three-argument form:

	```bash
	$ «script» path/to/backupdir «runtag» filename
	```

	This is effectively a blend of the first two forms. The path to the backup file is constructed by concatenation using the filename you supply instead of a default:

	```
	path/to/backupdir/«runtag».filename
	```

	If you use this form, remember to observe each script's assumption about the correct file-type «extensions» ([Table 1](#refExtensions)).

Each script exits without error if the input file constructed from its parameters does not exist. The [`iotstack_restore`](#iotstackRestore) umbrella script relies on this behaviour. It calls all the subordinate scripts unconditionally, assuming that the absence of a backup file implies that there is nothing to restore.

Each script starts by checking the status of its associated container(s). See [Table 3](#refContainers). The associated container(s) must **not** be running when the script starts and the script exits without creating a backup if this precondition is not met. The [`iotstack_restore`](#iotstackRestore) umbrella script always ensures the stack is down before calling its subordinate scripts so, in practice, the only time you have to worry about this is if you are invoking a *«container»* restore script directly.

The common pattern for the database restore scripts is:

1. Erase the associated container's persistent storage.
2. Start the container so it can self-initialise to "factory conditions".
3. Instruct the database engine to restore its databases from the backup.
4. Terminate the container.  

Note:

* The presence of a backup file for a container assumes the existence of a corresponding service definition in the compose file. Violating this assumption will lead to a mess.

	To put this another way, restoring a database container needs the involvement of the database engine. The only way the database engine can be made available to the restore script is if docker-compose can bring up the relevant container when commanded to do so by the script and that, in turn, relies on the existence of an appropriate service definition in the compose file.
	
	This is also why [`iotstack_restore_general`](#iotstackRestoreGeneral) runs first, because it is assumed to guarantee the presence of an appropriate compose file, particularly during a bare-metal restore. 

<a name="bareMetalRestore"></a>
## Bare-metal restore

Scenario. Your SD card wears out, or your Raspberry Pi emits magic smoke, or you decide the time has come for a fresh start. 

1. Use [PiBuilder](https://github.com/Paraphraser/PiBuilder) to construct a new operating system. Starting from a new SD card or SSD with a fresh Raspberry Pi OS image, PiBuilder:
 
	* Installs all the dependencies, including Docker and Docker-Compose
	* Installs all recommended system patches
	* Clones the [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack) repository
	* Clones and installs this IOTstackBackup repository; and
	* Will even install the following files, if you provide them to PiBuilder:

		```
		~/.config/rclone/rclone.conf
		~/.config/iotstack_backup/config.yml
		```

2. Run [`iotstack_restore`](#iotstackRestore) with the [«runtag»](#aboutRuntag) of a recent backup. Among other things, this will recover `docker-compose.yml` (ie there is no need to run the menu and re-select your services). As the various database containers are restored, a side-effect is to pull the container's image from DockerHub.
3. Bring up the stack. That pulls any remaining images from DockerHub and, as the saying goes, you're "up, up and away".

<a name="envVars"></a>
## Environment variables

IOTstackBackup supports the following environment variables:

* `IOTSTACK=`

	One of the key assumptions for IOTstack is that you begin by running:

	```bash
	$ git clone https://github.com/SensorsIot/IOTstack.git ~/IOTstack
	```

	IOTstackBackup relies on `~/IOTstack` being present and containing the expected files and folders. If you decide to use a different name for the top-level folder, you communicate this to IOTstackBackup using the `IOTSTACK` environment variable. For example:

	```bash
	$ IOTSTACK="$HOME/MyStack" iotstack_backup
	```

	> Whether all the scripts supplied with IOTstack will work, reliably, if you use a different top-level folder is a separate question. The point being made here is that IOTstackBackup supports it.
	 
	Similarly, if you wanted to backup just the InfluxDB databases:

	```
	$ IOTSTACK="$HOME/MyStack" iotstack_backup_influxdb backup-test-data.tar
	```

	You can also use the `IOTSTACK` environment variable if you have multiple copies of IOTstack installed on a single Raspberry Pi. For example, assume your home directory contains:

	```
	drwxr-xr-x 13 pi pi  4096 May 24 12:35 IOTstack
	drwxr-xr-x 13 pi pi  4096 May 24 12:35 IOTstack.test
	```

	If you want to backup the `IOTstack.test` directory, run:

	```bash
	$ IOTSTACK="$HOME/IOTstack.test" iotstack_backup $(date +"%Y-%m-%d_%H%M").$HOSTNAME.test
	```

	> Note the explicit [«runtag»](#aboutRuntag) parameter. This is to avoid colliding with existing backup sets if you are using the [*rsync*](#rsyncOption) or [*rclone*](#rcloneOption) methods to copy your backup files to another system. Also remember to create the corresponding *destination* top-level directory if you are using the [*scp*](#scpOption) or [*rsync*](#rsyncOption) methods.

* `CONTAINER=`

	This variable is supported by the [iotstack\_backup\_*«container»*](#iotstackBackupContainer) and [iotstack\_restore\_*«container»*](#iotstackRestoreContainer) scripts. 

	Suppose you have cloned the `mariadb` service definition and called it `mydb`. The IOTstack conventions you should observe in the service definition are:

	1. The title of the service definition is `mydb`.
	2. The `container_name` is `mydb`.
	3. The prefixes of the external paths in the `volumes` statements begin with:

		```yaml
		- ./volumes/mydb/
		```

	Providing you conform with those conventions, you can use the `CONTAINER` environment variable to backup and restore your container:

	```bash
	$ CONTAINER="mydb" iotstack_backup_mariadb mydb-backup.tar.gz
	$ CONTAINER="mydb" iotstack_restore_mariadb mydb-backup.tar.gz
	```

	> You will need to edit the [`iotstack_backup`](#iotstackBackup) and [`iotstack_restore`](#iotstackRestore) umbrella scripts if you want `mydb` processed automatically.

<a name="iotstackReloadInflux"></a>
## Reloading Influx databases "in situ"

Reloading InfluxDB databases can help address some performance issues and allow you to convert between indexing modes.

Usage:

* InfluxDB 1.8

	```bash
	$ iotstack_reload_influxdb
	```

* InfluxDB 2

	```bash
	$ iotstack_reload_influxdb2
	```

Each script:

1. Instructs the container to backup the current databases;
2. Takes the container down;
3. Erases existing persistent storage;
4. Starts the container (the container will reinitialise to "factory fresh");
5. Instructs the container to restore its databases from the backup taken in step 1.

There is some downtime while this process runs but it is kept to a minimum.

<a name="endNotes"></a>
## Notes

<a name="aboutRuntag"></a>
### about «runtag»

When omitted as an argument to [`iotstack_backup`](#iotstackBackup), «runtag» defaults to the current date-time value in the format *yyyy-mm-dd_hhmm* followed by the host name as determined from the HOSTNAME environment variable. For example:

```bash
$ RUNTAG=$(date +"%Y-%m-%d_%H%M").$HOSTNAME
$ echo $RUNTAG
2022-05-24_1138.iot-hub
```

The *yyyy-mm-dd_hhmm.hostname* syntax is assumed by both [`iotstack_backup`](#iotstackBackup) and [`iotstack_restore`](#iotstackRestore) but no checking is done to enforce this.

If you pass a value for «runtag», it must be a single string that does not contain characters that are open to misinterpretation by `bash`, such as spaces, dollar signs and so on.

The period character (".", aka "full stop") has a special meaning:

* everything to the **left** of the **first** period is assumed to be the DATETIME portion but does **not** have to be a valid date-time value;
* everything to the **right** of the **first** period is the HOSTNAME portion but does not have to be a valid host-name in the sense of existing on your network.

The period being special also implies:

* the DATETIME portion **can't** contain any periods;
* the HOSTNAME portion **can** contain periods; but
* supplying a «runtag» which doesn't contain at least one period will produce a mess.

The scripts will **not** protect you if you ignore these rules. You **will** create a mess and you have been warned!

<a name="nextcloudMaintenanceMode"></a>
### if Nextcloud gets stuck in "maintenance mode"

If Nextcloud backup fails, you may find that Nextcloud has been left in "maintenance mode" and you are locked out. To take Nextcloud out of maintenance mode:

```bash
$ docker exec -u www-data -it nextcloud php occ maintenance:mode --off
```

<a name="usingcron"></a>
### using cron to run iotstack\_backup

Resources:

* [crontab template](https://github.com/Paraphraser/PiBuilder/blob/master/boot/scripts/support/home/pi/crontab) - a good starting point
* [crontab guru](https://crontab.guru) - for checking crontab entries

Setup:

1. Scaffolding:

	```bash
	$ mkdir ~/Logs
	```

2. If you don't have an existing crontab, you can download this template and use it to initialise your system:

	```bash
	$ wget -qO my-crontab.txt https://raw.githubusercontent.com/Paraphraser/PiBuilder/master/boot/scripts/support/home/pi/crontab
	$ crontab my-crontab.txt
	$ rm my-crontab.txt
	```

3. Design one or more crontab entries to run [`iotstack_backup`](#iotstackBackup). For example, to run the command once a day at 11am:

	```
	# backup Docker containers and configurations once per day at 11:00am
	00	11	*	*	*	iotstack_backup >>./Logs/iotstack_backup.log 2>&1
	```

	See [crontab.guru](https://crontab.guru/#00_11_*_*_*) if you want to understand the syntax or try out alternatives.

	See [understanding logging when cron is involved](#cronLogging) if you want to know why command output needs to be redirected to `./Logs/iotstack_backup.log`.

4. Once you have designed your crontab entries, you need to edit your working crontab to include them:

	```bash
	$ crontab -e
	```

	That command uses the default Unix editor which you set using the `EDITOR` environment variable. As an alternative, you can export your working crontab to a text file:

	```bash
	$ crontab -l >my-crontab.txt
	```

	Then you can edit `my-crontab.txt ` using the text editor of your choice. Once you are ready and want to import your new crontab:

	```bash
	$ crontab my-crontab.txt
	```

<a name="cronLogging"></a>
#### understanding logging when cron is involved

Normally, [`iotstack_backup`](#iotstackBackup) writes its log to the path:

```
~/IOTstack/backups/yyyy-mm-dd_hhmm.hostname.backup-log.txt
```

That happens whether you run [`iotstack_backup`](#iotstackBackup) from the command line or via cron.

If something prevents that log file from being created (eg a permission conflict) when you run [`iotstack_backup`](#iotstackBackup) from the command line, you will get error messages to help you diagnose the problem.

That can't happen when [`iotstack_backup`](#iotstackBackup) is started by cron because there is no terminal session to write to. In this situation, the evidence you are likely to need to diagnose problems will be found in:

```
~/Logs/iotstack_backup.log
```

You may also find a "You have new mail" message on your next login.

<a name="spaceUtilisation"></a>
### monitoring disk space utilisation

If you are short on storage space, either on your Pi or on your remote (eg Dropbox), you might find the tutorial on [Monitoring Storage Quotas](monitoring-storage-quotas.md) useful.

<a name="periodicMaintenance"></a>
### periodic maintenance

From time to time, you should synchronise your local copy of the IOTstackBackup repository with GitHub and then reinstall the scripts:

```bash
$ cd ~/.local/IOTstackBackup
$ git checkout master
$ git pull
$ ./install_scripts.sh
```

<a name="tutorials"></a>
## Tutorials & Guides

* [Setting up SSH keys for password-less access](ssh-tutorial.md)
* [Taking a snapshot of your Raspberry Pi system](raspbian-system-snapshots.md)
* [Monitoring Storage Quotas](monitoring-storage-quotas.md)
* [Generating GnuPG Keys](generating-gpg-keys.md)
* [Restoring users, grants and continuous queries in InfluxDB 1.8](influxdb-post-processing.md)
