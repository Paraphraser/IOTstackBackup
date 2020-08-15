# IOTstack Backup and Restore

This project documents my approach to backup and restore of [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). My design goals were:

1. Avoid the double-compression implicit in the official backup script:
	* An InfluxDB backup produces .tar.gz files. Simply collecting those into a single .tar is more efficient than recompressing them into another .tar.gz.
2. Use `scp` to copy the backups from my "live" RPi to another machine on my local network. In my case, the target folder on that "other machine" is within the scope of Dropbox so I get three levels of backup:
	* The last five backups are stored on the local RPi in `~/IOTstack/backups/`
	* On-site copies on the "other machine"
	* Off-site copies in the Dropbox cloud. 
3. More consistent and `cron`-friendly logging of whatever was written to `stdout` and `stderr` as the backup script ran.
4. Efficient restore of a backup.

My scripts may or may not be directly useful in your situation. They are intended less as a drop-in replacement for the official backup script than they are as an example of an approach you might consider and adapt to your own needs.

In particular, these scripts will never be guaranteed to cover the full gamut of container types supported by [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack).

The scripts *should* work "as is" with any container type that can be backed-up safely by copying the contents of its `volumes` directory _while the container is running_. I call this the ***copy-safe*** property.

Databases (other than SQLite) are the main exception. Like the official backup script upon which it is based, `backup_iotstack` handles `InfluxDB` properly, omits `nextcloud` entirely, and completely ignores the problem for any container which is not *copy-safe* (eg PostgreSQL).

At the time of writing, there is no equivalent for `restore_iotstack` in [SensorsIot/IOTstack](https://github.com/SensorsIot/IOTstack). Running my `restore_iotstack` replaces the contents of the `services` and `volumes` directories, then restores the `InfluxDB` databases properly. Fairly obviously, `nextcloud` will be absent but any other non-*copy-safe* container may well be in a damaged state.

If you are running `nextcloud` or any container type which is not *copy-safe*, it is up to you to come up with an appropriate solution. Most database packages have their own backup & restore mechanisms. It is just a matter of working out what those are, how to implement them in a Docker environment, and then bolting that into your backup/restore scripts.

## setup

Clone or download the contents of this repository.

> In my case, I move the three scripts into `~/bin` which is in my `PATH` environment variable. See also [using cron](#usingcron).

### Option 1: use `scp`

If you want to follow my approach and use `scp` to copy the backups to another host, you will need to edit both `backup_iotstack` and `restore_iotstack` to change these three lines:

```
SCPNAME="myhost.mydomain.com"
SCPUSER="myuser"
SCPPATH="/path/to/backup/directory/on/myhost"
```

* «SCPNAME» can be a hostname, a fully-qualified domain name, or the IP address of another computer. The target computer does **not** have to be on your local network.
* «SCPUSER» is the username on the target computer.
* «SCPPATH» is the path to the target folder on the target computer.

You should test connectivity like this:

```
$ SCPNAME="serenity.firefly.com"
$ SCPUSER="wash"
$ SCPPATH="./Dropbox/IOTstack/backups"
$ touch test.txt
$ scp test.txt $SCPUSER@$SCPNAME:$SCPPATH
$ rm test.txt
$ scp $SCPUSER@$SCPNAME:$SCPPATH/test.txt .
```

Notes:

* «SCPPATH» should not contain embedded spaces or other characters that are open to misinterpretation by `bash`. If this is a deal-breaker then you will have to do the work of quoting $SCPPATH wherever it appears.
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
* attach a backup drive to your RPi and simply copy the backups.

### Option 3: invert the problem

It would also be perfectlty valid to omit any automatic copying steps from the RPi side of things. You could just as easily remote-mount the RPi's working drive on another computer and run a script there that copies the backups.

## script 1: backup_iotstack

> Acknowledgement: the `backup_iotstack` script was based on [Graham Garner's backup script](https://github.com/gcgarner/IOTstack/blob/master/scripts/docker_backup.sh) as at 2019-11-17.

Usage:

```
backup_iotstack {runtag}
```

* *runtag* is an _optional_ argument which defaults to the current date-time value in the format *yyyy-mm-dd_hhmm*. See also [about *runtag*](#aboutRuntag).

The script creates three files:

* *yyyy-mm-dd_hhmm.general-backup.tar.gz* contains:
	* `~/IOTstack/docker-compose.yml`
	* everything in `~/IOTstack/services`
	* everything in `~/IOTstack/volumes`, except:
		* `~/IOTstack/volumes/influxdb` and
		* `~/IOTstack/volumes/nextcloud`
* *yyyy-mm-dd_hhmm.influx-backup.tar* contains the InfluxDB backup
* *yyyy-mm-dd_hhmm.backup-log.txt* holds everything written to `stdout` and `stderr` as the script executed.

The three files are stored in `~/IOTstack/backups/` and copied to the target host using scp.

## script 2: restore_iotstack

Usage:

```
restore_iotstack runtag
```

* *runtag* is a _required_ argument which must exactly match the *runtag* used by the `backup_iotstack` you wish to restore. See also [about *runtag*](#aboutRuntag).

The script:

* Creates these temporary folders:
	* `~/IOTstack/restore`
	* `~/IOTstack/restore/general`
* Uses `scp` to copy *yyyy-mm-dd_hhmm.general-backup.tar.gz* and *yyyy-mm-dd_hhmm.influx-backup.tar* from the target computer into `~/IOTstack/restore`
* Unpacks *yyyy-mm-dd_hhmm.general-backup.tar.gz* into `~/IOTstack/restore/general`
* Takes the stack down
* Removes the old `~/IOTstack/services` and `~/IOTstack/volumes` directories
* Moves the restored `services` and `volumes` directories into `~/IOTstack`
* Moves the restored `docker-compose.yml` into `~/IOTstack` as `docker-compose.yml.runtag`
* Unpacks *yyyy-mm-dd_hhmm.influx-backup.tar* into `~/IOTstack/backups/influxdb/db`
* Brings the stack up (at which point the InfluxDB databases will be empty)
* Instructs InfluxDB to restore from the contents of `~/IOTstack/backups/influxdb/db`. See also [about InfluxDB database restoration](#aboutInfluxRestore) 
* Removes `~/IOTstack/restore` and its contents.

My usual work pattern is that I am restoring to a "test" RPi a backup taken on a "live" RPi. I also often edit `docker-compose.yml` on the "test" RPi before making equivalent changes on the "live" RPi. That's why the script does not replace `docker-compose.yml`. Change that behaviour if it doesn't suit your own needs.

## script 3: reload_influxdb

Usage:

```
reload_influxdb
```

I wrote this script because I noticed a difference in behaviour between my "live" and "test" RPis. Executing this command:

```
$ docker exec -it influxdb bash
```

on the "live" RPi was extremely slow (30 seconds). On the "test" RPi, it was almost instantaneous. The hardware was indentical. The IOTstack installation identical, the Docker image versions for InfluxDB were identical. The only plausible explanation was that the InfluxDB databases on the "live" RPi had grown organically whereas the databases on the "test" RPi were routinely restored by `restore_iotstack`.

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

When omitted as an argument to `backup_iotstack`, *runtag* defaults to the current date-time value in the format *yyyy-mm-dd_hhmm*.

The *yyyy-mm-dd_hhmm* syntax is assumed by both `backup_iotstack` and `restore_iotstack` but no checking is done to enforce this.

If you pass a value for *runtag*, it must be a single string that does not contain characters that are open to misinterpretation by `bash`, such as spaces, dollar signs and so on.

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

### <a name="usingcron">using `cron` to run `backup_iotstack` </a>

I do it like this.

1. Scaffolding:

	```
	$ mkdir ~/IOTstack/Logs
	$ touch ~/IOTstack/Logs/backup_iotstack.log
	```

2. crontab entry:

	```
	# backup Docker containers and configurations once per day at 11:00am
	00	11	*	*	*	./bin/backup_iotstack >>./Logs/backup_iotstack.log 2>&1
	```

If everything works as expected, `~/IOTstack/Logs/backup_iotstack.log` will be empty. The actual log is written to *yyyy-mm-dd_hhmm.backup-log.txt* inside `~/IOTstack/backups`.

When things don't go as expected (eg a permissions issue), the information you will need for debugging will turn up in `~/IOTstack/Logs/backup_iotstack.log` and you may also find a "You have new mail" message on your next login.
