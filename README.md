# IOTstack Backup and Restore

This project documents my approach to backup and restore of [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). My design goals were:

1. Avoid the double-compression implicit in the official backup scripts:
	* An InfluxDB portable backup produces .tar.gz files. Simply collecting those into a separate .tar is more efficient than recompressing them into a .tar.gz.
2. Use `scp` to copy the backups from my "live" RPi to another machine on my local network. In my case, the target folder on that "other machine" is within the scope of Dropbox so I get three levels of backup:
	* Recent backups are stored on the local RPi in `~/IOTstack/backups/`
	* On-site copies on the "other machine"
	* Off-site copies in the Dropbox cloud. 
3. More consistent and `cron`-friendly logging of whatever was written to `stdout` and `stderr` as the backup script ran.
4. Efficient restore of a backup, including in a "bare-metal" restore.

My scripts may or may not be directly useful in your situation. They are intended less as a drop-in replacement for the official backup script than they are as an example of an approach you might consider and adapt to your own needs.

In particular, these scripts will never be guaranteed to cover the full gamut of container types supported by [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack).

The scripts *should* work "as is" with any container type that can be backed-up safely by copying the contents of its `volumes` directory _while the container is running_. I call this the ***copy-safe*** property.

Databases (other than SQLite) are the main exception. Like the official backup script upon which it is based, `iotstack_backup` handles `InfluxDB` properly, omits `nextcloud` entirely, and completely ignores the problem for any container which is not *copy-safe* (eg PostgreSQL).

At the time of writing, there is no equivalent for `iotstack_restore` in [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). Running my `iotstack_restore` replaces the contents of the `services` and `volumes` directories, then restores the `InfluxDB` databases properly. Fairly obviously, `nextcloud` will be absent but any other non-*copy-safe* container may well be in a damaged state.

If you are running `nextcloud` or any container type which is not *copy-safe*, it is up to you to come up with an appropriate solution. Most database packages have their own backup & restore mechanisms. It is just a matter of working out what those are, how to implement them in a Docker environment, and then bolting that into your backup/restore scripts.

## setup

Clone or download the contents of this repository.

> In my case, I move the scripts into `~/bin` which is in my `PATH` environment variable. See also [using cron](#usingcron).

### Option 1: use `scp`

If you want to follow my approach and use `scp` to copy the backups to another host, you will need to edit both `iotstack_backup` and `iotstack_restore` to change these three lines:

```
SCPHOST="myhost.mydomain.com"
SCPUSER="myuser"
SCPPATH="/path/to/backup/directory/on/myhost"
```

* «SCPHOST» can be a hostname, a fully-qualified domain name, or the IP address of another computer. The target computer does **not** have to be on your local network.
* «SCPUSER» is the username on the target computer.
* «SCPPATH» is the path to the target folder on the target computer.

You should test connectivity like this:

```
$ SCPHOST="serenity.firefly.com"
$ SCPUSER="wash"
$ SCPPATH="./Dropbox/IOTstack/backups"
$ touch test.txt
$ scp test.txt $SCPUSER@$SCPHOST:$SCPPATH
$ rm test.txt
$ scp $SCPUSER@$SCPHOST:$SCPPATH/test.txt .
```

Notes:

* «SCPPATH» should not contain embedded spaces or other characters that are open to misinterpretation by `bash`. If this is a deal-breaker then you will have to do the work of making sure that $SCPPATH is quoted properly wherever it appears.
* the target directory defined by «SCPPATH» must exist and be writeable by «SCPUSER».
* in the case of «SCPPATH» a leading "." normally means "the home directory of «SCPUSER» on the target machine. You can also use an absolute path (ie starting with a "/").
* the trailing "." on the second `scp` command means "the working directory on the RPi where you are running the command".
* in both `scp` commands, "test.txt" is implied on the right hand side.

Your goal is that both of the `scp` commands should work without prompting for passwords or the need to accept fingerprints:

* Avoiding password prompts is generally a matter of using `ssh-keygen` to generate a key-pair on the RPi, then copying the public key to the target computer (eg with `ssh-copy-id`) and concatenating it to the authorized_keys file on the target.
* Fingerprint prompts are mostly one-time events but can recur if your devices change their IP addresses (eg the IP address is assigned from a DHCP server's dynamic pool). You can avoid this by using static DHCP assignments (if you can) or static IP addresses (if you have no other choice).

> The exact how-to of ssh setup is beyond the scope of this ReadMe. Google is your friend.

### Option 2: roll your own

If you don't want to use `scp`, you could:

* re-implement one of the cloud approaches in the original [docker_backup.sh](https://github.com/SensorsIot/IOTstack/blob/master/scripts/docker_backup.sh)
* come up with another cloud backup mechanism of your own choosing
* attach a backup drive to your RPi and simply copy the backup files.

### Option 3: invert the problem

It would be perfectly valid to omit any automatic copying steps from the RPi side of things. You could just as easily remote-mount the RPi's working drive on another computer and run a script there that copies the backups.

## The backup side of things

There are three scripts:

* `iotstack_backup_general` – backs-up everything<sup>†</sup> except InfluxDB databases
* `iotstack_backup_influxdb` – backs-up InfluxDB databases
* `iotstack_backup` – a supervisory script which calls both of the above and handles copying of the results to another host via `scp`.

	† "everything" is a slightly loose term. See below.

In general, `iotstack_backup` is the script you should call.

> Acknowledgement: the backup scripts were based on [Graham Garner's backup script](https://github.com/gcgarner/IOTstack/blob/master/scripts/docker_backup.sh) as at 2019-11-17.

### script 1: iotstack\_backup\_general

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
	* All files matching the pattern `~/IOTstack/docker-compose.*`
	* everything in `~/IOTstack/services`
	* everything in `~/IOTstack/volumes`, except:
		* `~/IOTstack/volumes/influxdb`
		* `~/IOTstack/volumes/nextcloud`
		* `~/IOTstack/volumes/postgres`<sup>†</sup>
		* `~/IOTstack/volumes/pihole.restored `

	† *postgres* is omitted because it is not copy-safe but there is, as yet, no script to backup PostGres like there is for InfluxDB. If you run PostGres and you want to take the risk, just remove the exclusion from the script.

The reason for implementing this as a standalone script is to make it easier to take snapshots and/or build your own backup strategy.

Example:

```
$ cd
$ mkdir my_special_backups
$ cd my_special_backups
$ iotstack_backup_general before_major_changes.tar.gz
```

### script 2: iotstack\_backup\_influxdb

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

### script 3: iotstack\_backup

Usage:

```
iotstack_backup {runtag}
```

* *runtag* is an _optional_ argument which defaults to the current date-time value in the format *yyyy-mm-dd_hhmm* followed by the host name obtained from the $HOSTNAME environment variable. For example:

	```
	2020-09-19_1138.iot-hub
	```

The script invokes `iotstack_backup_general` and `iotstack_backup_influxdb` (in that order) and leaves the results in `~/IOTstack/backups` along with a log file containing everything written to `stdout` and `stderr` as the script executed. Given the example *runtag* above, the resulting files would be:

```
~/IOTstack/backups/2020-09-19_1138.iot-hub.backup-log.txt
~/IOTstack/backups/2020-09-19_1138.iot-hub.general-backup.tar.gz
~/IOTstack/backups/2020-09-19_1138.iot-hub.influx-backup.tar
```

The files are copied to the target host using `scp` (or whatever substitute method you supply) and then `~/IOTstack/backups` is cleaned up to remove older backups.


## The restore side of things

There are three scripts which provide the inverse functionality of the backup scripts:

* `iotstack_restore_general ` – restores everything present in the general backup
* `iotstack_restore_influxdb ` – restores InfluxDB databases
* `iotstack_restore` – a general restore which calls both of the above

In general, `iotstack_restore` is the script you should call.

### script 1: iotstack\_restore\_general

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
		* `~/IOTstack/volumes/nextcloud`
		* `~/IOTstack/volumes/postgres`<sup>†</sup>
		* `~/IOTstack/volumes/pihole.restored `
	* `~/IOTstack/docker-compose.yml` in some situations.

	† if you removed the `postgres` exclusion from `iotstack_backup_general` then the postgres directory will be restored in as-backed-up state.
	
`docker-compose.yml` is given special handling:

* If `docker-compose.yml` is **not** present in `~/IOTstack` then `docker-compose.yml` will be restored from *path_to.tar.gz*.
* If `docker-compose.yml` **is** present in `~/IOTstack` then `docker-compose.yml` in `~/IOTstack` will be compared with `docker-compose.yml` from *path_to.tar.gz*. If and only if the two files do not compare the same, `docker-compose.yml` from *path_to.tar.gz* will be restored into `~/IOTstack` with a date-time suffix.

The reason for implementing the "general" restore as a standalone script is to make it easier to manage snapshots and/or build your own backup strategy.

Example:

```
$ cd ~/my_special_backups
$ iotstack_restore_general before_major_changes.tar.gz
```

### script 2: iotstack\_restore\_influxdb

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

### script 3: iotstack_restore

Usage:

```
iotstack_restore runtag
```

* *runtag* is a _required_ argument which must exactly match the *runtag* used by the `iotstack_backup` you wish to restore. For example:

```
$ iotstack_restore 2020-09-19_1138.iot-hub
```

The script:

* Creates a temporary directory within `~/IOTstack`
* Uses `scp` to copy files matching the pattern *runtag.\** into the temporary directory
* Deactivates your stack (if at least one container is running)
* Invokes `iotstack_restore_general`
* Invokes `iotstack_restore_influxdb`
* Cleans-up the temporary directory
* Reactivates your stack if it was deactivated by this script.

Both `iotstack_restore_general` and `iotstack_restore_influxdb` are invoked with two arguments:

* The path to the temporary restore directory; and
* The *runtag*.

Each script assumes that the path to its backup file can be derived from those two arguments. This will be true if the backup was created by `iotstack_backup` but is something to be aware of if you roll your own solution.

## Bare-metal restore

Scenario. Your SD card wears out, or your Raspberry Pi emits magic smoke, or you decide the time has come for a fresh start:

1. Image a new SD card and/or build an SSD image.
2. Install all the necessary (git, curl) and desirable packages (acl, jq, sqlite3, uuid-runtime, wget).
3. Clone [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack).
4. Run the IOTstack menu and install Docker.
5. Reboot.
6. Run `iotstack_restore` with the runtag of a recent backup. Among other things, this will recover `docker-compose.yml` (ie there is no need to run the menu and re-select your services).
7. Bring up the stack.

## iotstack\_reload\_influxdb

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

## Notes

### <a name="aboutRuntag">about *runtag*</a>

When omitted as an argument to `iotstack_backup`, *runtag* defaults to the current date-time value in the format *yyyy-mm-dd_hhmm* followed by the host name as determined from the `$HOSTNAME` environment variable. For example:

```
2020-09-19_1138.iot-hub
```

The *yyyy-mm-dd_hhmm.hostname* syntax is assumed by both `iotstack_backup` and `iotstack_restore` but no checking is done to enforce this.

If you pass a value for *runtag*, it must be a single string that does not contain characters that are open to misinterpretation by `bash`, such as spaces, dollar signs and so on.

There is also an implied assumption that `$HOSTNAME` does not contain spaces or special characters.

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

### <a name="usingcron">using `cron` to run `iotstack_backup` </a>

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
	PATH=/home/pi/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	```
3. crontab entry:

	```
	# backup Docker containers and configurations once per day at 11:00am
	00	11	*	*	*	iotstack_backup >>./Logs/iotstack_backup.log 2>&1
	```

If everything works as expected, `~/Logs/iotstack_backup.log` will be empty. The actual log is written to *yyyy-mm-dd_hhmm.backup-log.txt* inside `~/IOTstack/backups`.

When things don't go as expected (eg a permissions issue), the information you will need for debugging will turn up in `~/Logs/iotstack_backup.log` and you may also find a "You have new mail" message on your next login.
