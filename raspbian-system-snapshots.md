# Taking a snapshot of your Raspberry Pi system

Creating a full backup of a Raspberry Pi is a bit of a challenge. Whichever approach you use can take a lot of time and a lot of storage space. It also isn't really practical on a "live" system because of the way files are changing constantly. In general, the only way to be absolutely certain that you have a *coherent* backup is to take your active storage media (SD or SSD) offline and use an imaging tool. That means you're without your Pi's services for the duration of the backup process.

Raspberry Pi failures can be categorised into those that affect the Pi itself, and those that affect your storage media. If your Pi has emitted magic smoke but the media is otherwise undamaged then, most of the time, you can move the media to a new Pi (if you can get one). You might need to tweak your DHCP configuration to use the new MAC address(es) but that's about it.

If your media has gone splat and you happen to have a reasonably up-to-date image, you can probably get away with restoring that image to the same or new media but you also take the risk that you are restoring the very conditions that led to the media failure in the first place. You are usually better advised to cut your losses and start with a clean image of Raspberry Pi OS.  

If you use [PiBuilder](https://github.com/Paraphraser/PiBuilder) to build your Raspberry Pi OS, it will clone IOTstack plus install docker and docker-compose along with all their dependencies and useful packages. If you have been sufficiently diligent about maintaining your own clone of PiBuilder, it can make a fair fist of rebuilding your Pi "as it was" with customised configuration files in `/boot`, `/etc` and so on.

If you use `iotstack_backup` then recovering your IOTstack can be as simple as:

```
$ iotstack_restore «runtag»
$ cd ~/IOTstack
$ docker-compose up -d
```

But there will still probably be a few gaps, such as:

* the content of your home directory outside of IOTstack;
* the content of other user accounts you may have created;
* recent configuration decisions you implemented in `/etc` which you haven't yet gotten around to adding to PiBuilder;
* your crontab;
* …

The gaps are where the `snapshot_raspbian_system` script can help.

The script follows the same minimalist "only backup things that can't be reconstructed from elsewhere" philosophy as the rest of IOTstackBackup.

There is, however, no matching "restore" script. The basic idea of a *snapshot* is a *resource* from which you can cherry-pick items, evaluate each for ongoing suitability, then move them into place by hand. A snapshot will help you answer questions like:

* How did I have `/etc/resolvconf.conf` set up?
* What was in `~/.ssh/authorized_keys`?
* I know I had Git repository X cloned from somewhere but what was the URL?

## Contents

- [Installation](#installation)

	- [Configuration](#configuration)

- [First run](#firstRun)
- [Second or subsequent run](#secondRun)

	- [Automatic exclusions](#autoExclusions)
	- [Override markers](#forceOverride)

		- [forcing inclusion](#forceInclude)
		- [forcing exclusion](#forceExclude)
		- [override marker conflicts](#forceBoth)
		- [nested override markers](#forceNesting)

	- [Script result](#scriptOutputPlain)
	- [Automatic encryption with GnuPG (optional)](#scriptOutputCrypt)

		- [Encryption details](#cryptoDetails)

- [Script argument (optional)](#scriptArg)

- [Version control systems](#vcs)

	- [git](#vcsGit)
	- [subversion](#vcsSvn)

- [Log examples](#logExamples)

	- [`~/IOTstack` (git repository)](#logGit1)
	- [`~/.local/IOTstackBackup` (git repository)](#logGit2)
	- [a subversion example](#logSvn)
	- [`~/.local/lib`](#logExclude)

- [Tips and tricks](#tipsNtricks)

	- [Extracting a snaphot](#tipExtract)
	- [checking ownership and permissions](#tipsOwner)
	- [change discovery](#tipsDiff)
	- [symlinks - known weakness](#tipsSymlinks)

<a name="installation"></a>
## Installation

The snapshot script is part of IOTstackBackup. It will be installed along with the other scripts when you follow the steps at [download the repository](README.md#downloadRepository).

> If you are an existing user of IOTstackBackup, please follow the [periodic maintenance](README.md#periodicMaintenance) instructions.

<a name="configuration"></a>
### Configuration

The snapshot script piggy-backs off your IOTstackBackup configuration settings which are stored in:

```
~/.config/iotstack_backup/config.yml
```

If you have not yet set up that file, please work through the [configuration file](README.md#configFile) steps.

When saving snapshots on the remote system, the `snapshot_raspbian_system` script behaves a little differently than the `iotstack_backup` script. Assume the following example configurations:

- either:

	```
	backup method = SCP or RSYNC
	remote prefix = user@host:/path/IoT-Hub/backups
	```

- or:

	```
	backup method = RCLONE
	remote prefix = dropbox:IoT-Hub/backups
	```

The string `snapshot_raspbian_system` is appended to the prefix, as in:

- `user@host:/path/IoT-Hub/backups/snapshot_raspbian_system` or

- `dropbox:IoT-Hub/backups/snapshot_raspbian_system`

The `snapshot_raspbian_system` directory on the remote system is where snapshots are saved.

Key points:

* Irrespective of whether you are using SCP, RSYNC or RCLONE as your backup method, the remote copy performed by `snapshot_raspbian_system` is a *file* operation, not a *directory* operation. There is no "synchronisation" between local and remote directories.
* The retain count does not apply so there is no automatic cleanup. Keep this in mind if you decide to run this script from `cron` on a daily basis.

<a name="firstRun"></a>
## First run

The first time you run the script it will initialise a default <a name="backupList"></a>list of inclusions:

```
$ snapshot_raspbian_system
/home/pi/.config/iotstack_backup/snapshot_raspbian_system-inclusions.txt initialised from defaults:
  /etc
  /etc-baseline
  /var/spool/cron/crontabs
  /home
```

Those paths are the starting points for each snapshot. Together, they capture the most common locations for customisations of your Raspberry Pi OS.

You can edit `snapshot_raspbian_system-inclusions.txt` to add or remove paths (directories or files) as needed.

Notes:

* [PiBuilder](https://github.com/Paraphraser/PiBuilder) makes the following copies in its 01 script:

	- within either `/boot/firmware` (Bookworm and later) or `/boot` (Bullseye and earlier):

		- `config.txt` is copied as `config.txt.baseline`
		- `cmdline.txt` is copied as `cmdline.txt.baseline`

	- the entire `/etc` directory is copied as `/etc-baseline`

	The intention is that you will always have reference copies of files and folder structures "as shipped" with your Raspberry Pi OS image immediately after its first boot.
	
	Between them, the three baseline items should be able to help you answer the question, "what have I done to change my running system from its defaults?"
	
	The baseline items are included in each snapshot so you can still answer that question when your system is broken and you need to rebuild it.
	
	If you did not use [PiBuilder](https://github.com/Paraphraser/PiBuilder) then the baseline reference copies may not be present but their absence will not cause the snapshot script to fail.
	
* Even though they do not appear in the [list of inclusions](#backupList), each snapshot automatically includes any files matching the following patterns:

	```
	/boot/config.txt*
	/boot/cmdline.txt*
	/boot/firmware/config.txt*
	/boot/firmware/cmdline.txt*
	```
	
	In other words, if you also follow the convention of maintaining `.bak` files, those will get included along with the `.baseline` files.

<a name="secondRun"></a>
## Second or subsequent run

On a second or subsequent run, the script will:

1. Snapshot your system using the [list of inclusions](#backupList) to guide its activities;
2. Optionally encrypt the resulting `.tar.gz`; and
3. Save the result to your configured remote.

As the script is running, everything is written into a temporary directory. This avoids potential chicken-and-egg problems such as what happens if the backup files are being written into a directory that you then you add to the [list of inclusions](#backupList).

At the end of the run, the snapshot is copied off the local machine using whichever of SCP, RSYNC or RCLONE is in effect. Then the temporary directory is erased. Once the script has finished, the only place the snapshot exists is the remote machine.

This is an example run, with encryption enabled, where the result is transmitted to Dropbox:

```
$ GPGKEYID=88F86CF116522378 snapshot_raspbian_system 

----- Starting snapshot_raspbian_system at Thu 05 Jan 2023 17:33:30 AEDT -----
Environment:
    Script marker = snapshot_raspbian_system
     Search paths = /home/pi/.config/iotstack_backup/snapshot_raspbian_system-inclusions.txt
   Exclude marker = .exclude.snapshot_raspbian_system
   Include marker = .include.snapshot_raspbian_system
     Cloud method = RCLONE
  Cloud reference = dropbox:IoT-Hub/backups/snapshot_raspbian_system
Scanning:
  /etc
  /etc-baseline
  /var/spool/cron/crontabs
  /home
Paths included in the backup:
  /etc
  /etc-baseline
  /var/spool/cron/crontabs
  /home
  /boot/cmdline.txt
  /boot/cmdline.txt.bak
  /boot/cmdline.txt.baseline
  /boot/config.txt
  /boot/config.txt.baseline
  /dev/shm/backup_annotations_uwfIL6.txt
Paths excluded from the backup:
  /home/pi/.local/IOTstackBackup
  /home/pi/.local/IOTstackAliases
  /home/pi/PiBuilder
  /home/pi/IOTstack
  /home/pi/.local/bin
  /home/pi/.local/lib
  /home/pi/.cache
Encrypting the backup using --recipient 88F86CF116522378
Using rclone to copy the result off this machine
2023/01/05 17:33:45 INFO  : 2023-01-05_1733.sec-dev.raspbian-snapshot.tar.gz.gpg: Copied (new)
2023/01/05 17:33:45 INFO  : 
Transferred:   	    3.483 MiB / 3.483 MiB, 100%, 594.492 KiB/s, ETA 0s
Transferred:            1 / 1, 100%
Elapsed time:         7.8s

2023/01/05 17:33:45 INFO  : Dropbox root 'IoT-Hub/backups/snapshot_raspbian_system': Committing uploads - please wait...
----- Finished snapshot_raspbian_system at Thu 05 Jan 2023 17:33:45 AEDT -----
```

<a name="autoExclusions"></a>
### Automatic exclusions

The script iterates the [list of inclusions](#backupList). For each item that is a directory (eg `/home`), the directory structure is searched for subdirectories named `.git` or `.svn`. Each parent directory containing either a `.git` or `.svn` subdirectory is automatically excluded from the backup.

> The rationale is that such directories can be recovered using Git or Subversion.

Rather than expecting you to remember all the excluded directories and the URLs needed to recover them from their respective repositories, the backup log lists the excluded directories along with sufficient information for you to be able to run `git clone` and `svn checkout` commands.

No attempt is made to save any uncommitted files as part of the backup. The log simply records what you may need to reconstruct by other means. 

The script also automatically excludes any directories named `.cache` on the assumption that those will be recreated on demand.

<a name="forceOverride"></a>
### Override markers

You can override the default behaviour to either force the inclusion of a directory that would otherwise be excluded automatically, or force the exclusion of a directory that is being included automatically. 

<a name="forceInclude"></a>
#### forcing inclusion

If a directory is being excluded automatically but you decide that it should be included, you can force its inclusion by adding a marker file to the directory. For example:

``` console
$ cd directory/you/want/to/include
$ touch .include.snapshot_raspbian_system
```

The scope of include markers is limited to directories that would otherwise be excluded automatically. You can't create an include marker in some random place like `/var/log` and expect the script to go find it.

> You can, of course, modify the [list of inclusions](#backupList) to include `/var/log`.

<a name="forceExclude"></a>
#### forcing exclusion

If a directory is being included in your backup but you decide it can be reconstructed more easily by other means, you can exclude it by adding a marker file to the directory.

The path `~/.local/lib` is a good example of a directory you may wish to exclude:

``` console
$ cd ~/.local/lib
$ touch .exclude.snapshot_raspbian_system
```

The scope of exclude markers is limited to directories in the [list of inclusions](#backupList).

<a name="forceBoth"></a>
#### override marker conflicts

If a directory contains both an include and an exclude marker, the include marker prevails.

<a name="forceNesting"></a>
#### nested override markers

The `tar` application is passed two lists: a set of paths for inclusion, and a set of paths for exclusion. In any situation involving nested directories where items in the two lists might appear to create a paradox, `tar` is the final arbiter of what gets included in the snapshot. 

<a name="scriptOutputPlain"></a>
### Script result

The result of running `snapshot_raspbian_system` is a file named in the following format:

```
yyyy-mm-dd_hhmm.hostname.raspbian-snapshot.tar.gz
```

<a name="scriptOutputCrypt"></a>
### Automatic encryption with GnuPG (optional)

By default, directories like `~/.ssh` and `/etc/ssh` will be included in your snapshots. Those directories *may* contain sufficient information to help an attacker gain access to or impersonate your systems.

You *could* [exclude](#forceExclude) those directories from the backup. On the other hand, you may wish to ensure the contents of those directories are backed-up and ready to hand if you ever have to rebuild your Raspberry Pi.

You can resolve this conundrum by encrypting the snapshot. If `gpg` is installed and the environment variable `GPGKEYID` points to a valid public key in your keychain, the script will encrypt the snapshot using that keyID as the recipient and indicate this by appending the `.gpg` extension.

If you need help setting up GnuPG keys, please see [this tutorial](generating-gpg-keys.md).

<a name="cryptoDetails"></a>
#### Encryption details

The command used to encrypt the `.tar.gz` is:

```
$ gpg --recipient "$GPGKEYID" \
  --output yyyy-mm-dd_hhmm.hostname.raspbian-snapshot.tar.gz.gpg \
  --encrypt yyyy-mm-dd_hhmm.hostname.raspbian-snapshot.tar.gz
```

Encryption only needs the public key. The script checks for the presence of the public key in your keychain and will warn you if it is not found.

This form of encryption produces a "binary" output rather than an ASCII "armoured" output.

To decrypt the file, you would use:

```
$ gpg \
  --output yyyy-mm-dd_hhmm.hostname.raspbian-snapshot.tar.gz \
  --decrypt yyyy-mm-dd_hhmm.hostname.raspbian-snapshot.tar.gz.gpg
```

Decryption needs access to your private key and that, in turn, may need additional steps such as entering a passcode and/or unlocking and touching a token like a YubiKey.

It should be self-evident that you should make sure you can decrypt your encrypted snapshots **before** you have to rely on them!

<a name="scriptArg"></a>
## Script argument (optional)

By default, the `snapshot_raspbian_system` script uses its own name for the following:

* the path to the <a name="backupList"></a>list of inclusions:

	- `~/.config/iotstack_backup/snapshot_raspbian_system-inclusions.txt`

* the include and exclude markers: 

	- `.include.snapshot_raspbian_system`
	- `.exclude.snapshot_raspbian_system`

* the directory name on the remote system into which snapshots are stored:
	
	- `… IoT-Hub/backups/snapshot_raspbian_system`

You can change this behaviour passing an optional argument to the script. For example, running the following command:

``` console
$ snapshot_raspbian_system snapshot-for-me
```

will result in:

* the path to the list of inclusions being:

	- `~/.config/iotstack_backup/snapshot-for-me-inclusions.txt`

* the include and exclude markers being: 

	- `.include.snapshot-for-me`
	- `.exclude.snapshot-for-me`

* the directory name on the remote system into which snapshots are stored being:
	
	- `… IoT-Hub/backups/snapshot-for-me`

The ability to influence path and marker names is intended to help you tailor your snapshots to different situations. You can create custom [lists of inclusions](#backupList) and custom [inclusion](#forceInclude) and [exclusion](#forceExclude) override schemes that control the content of any snapshots. 

Nevertheless, because remote operations are involved, you should try to avoid passing arguments containing spaces or other characters that are open to misinterpretation by BASH. The script does its best to handle these correctly but it can't account for all possible interpretations by remote systems.

<a name="vcs"></a>
## Version control systems

<a name="vcsGit"></a>
### git

In any git repository on a Raspberry Pi, one of two things will be true:

1. The local repository is a clone of an upstream repository where you started by doing something like:

	``` console
	$ git clone URL myrepo
	```

	In this case, local modifications can be saved to a remote system via git `add`, `commit` and `push` commands. If you don't have commit rights on the upstream repository, you should consider forking the upstream repository. The implication is that a subsequent `git clone` will recover your local modifications.

2. The local repository is the authoritative instance. In other words, you started by doing something like:

	``` console
	$ mkdir myrepo
	$ cd myrepo
	$ git init
	```

	This case is an example of  where you should consider:

	* establishing an upstream remote you can `push` to; and/or
	* adding an [inclusion marker](#forceInclude) to the directory so that it is included in the snapshot.

<a name="vcsSvn"></a>
### subversion

With subversion, it is far more common to checkout from a remote repository:

``` console
$ svn checkout URL myrepo
```

If you make local changes, those can be added (if new) and committed, where a commit implies a push to the remote repository.

<a name="logExamples"></a>
## Log examples

<a name="logGit1"></a>
### `~/IOTstack` (git repository)

The path `~/IOTstack` is excluded because it contains `~/IOTstack/.git`. The resulting log entry is:

```
----- [snapshot_raspbian_system] ----- excluding /home/pi/IOTstack
origin	https://github.com/SensorsIot/IOTstack.git (fetch)
origin	https://github.com/SensorsIot/IOTstack.git (push)
On branch master
Your branch is up to date with 'origin/master'.

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	.env

nothing added to commit but untracked files present (use "git add" to track)
```

That tells you that you can recover that directory as follows:

```
$ git clone https://github.com/SensorsIot/IOTstack.git /home/pi/IOTstack
```

The reason why `.env` shows up as untracked while files like `docker-compose.yml` and directories like `backup`, `services` and `volumes` do not show up is `.env` is not in IOTstack's standard `.gitignore` list while the others are.

As it happens, `iotstack_backup` does backup `.env` along with the other files and directories mentioned above so this is a side-effect you can ignore.

<a name="logGit2"></a>
### `~/.local/IOTstackBackup` (git repository)

This directory is excluded because it contains a `.git` subdirectory. The log entry is:

```
----- [snapshot_raspbian_system] ----- excluding /home/pi/.local/IOTstackBackup
origin	https://github.com/Paraphraser/IOTstackBackup.git (fetch)
origin	https://github.com/Paraphraser/IOTstackBackup.git (push)
On branch master
Your branch is up to date with 'origin/master'.

nothing to commit, working tree clean
```

Again, this tells you that you can recover the directory via:

```
$ git clone https://github.com/Paraphraser/IOTstackBackup.git /home/pi/.local/IOTstackBackup
```

<a name="logSvn"></a>
### a subversion example

```
----- [snapshot_raspbian_system] ----- excluding /home/pi/.local/bin
svn://svnserver.my.domain.com/trunk/user/local/bin
```

The directory can be reconstructed with:

```
$ svn checkout svn://svnserver.my.domain.com/trunk/user/local/bin /home/pi/.local/bin
```

<a name="logExclude"></a>
### `~/.local/lib`

This directory is not excluded by default but can be excluded by creating an [exclusion marker](#forceExclude). The resulting log entry reports the exclusion with no additional details:

```
----- [snapshot_raspbian_system] ----- excluding /home/pi/.local/lib
```

This directory is a byproduct of other installations (ie is recreated automatically).

<a name="tipsNtricks"></a>
## Tips and tricks

Assume the following snapshot:

```
2023-01-05_1733.sec-dev.raspbian-snapshot.tar.gz
```

> If the file is still encrypted (ie has a `.gpg` extension), see [encryption details](#cryptoDetails) for an example of how to decrypt it. 

<a name="tipExtract"></a>
### Extracting a snaphot

The contents of a snapshot can be extracted like this:

```
$ mkdir extract
$ tar -C extract -xzf 2023-01-05_1733.sec-dev.raspbian-snapshot.tar.gz
tar: Removing leading '/' from member names
$ cd extract
```

The working directory will contain everything recovered from the snapshot.

<a name="tipsOwner"></a>
### checking ownership and permissions

One of the problems you will run into when you extract a tar in the manner described above is that ownership will be assigned to the current user. In other words, the contents of directories like `/etc` will not be owned by root.

Although you can pass an option to `tar` to cause it to retain the original ownership, that isn't always appropriate because you may well be doing the extraction on your support host (macOS or Windows) where the user and group IDs differ from those in effect on the Raspberry Pi when the `tar` archive was created. You also need to use `sudo` and that can be unwise (eg see [symlinks](#tipsSymlinks) below).

It's usually more convenient to answer questions about ownership and permissions by inspecting the archive. For example, what is the correct ownership and permission mode on `/etc/resolvconf.conf`?

```
$ tar -tvzf 2023-01-05_1733.sec-dev.raspbian-snapshot.tar.gz | grep "/etc/resolvconf.conf"
-rw-r--r--  0 root   root      500 Jan  3  2021 /etc/resolvconf.conf.bak
-rw-r--r--  0 root   root      625 Oct 25 23:11 /etc/resolvconf.conf
```

<a name="tipsDiff"></a>
### change discovery

The `diff` tool is one of the Unix world's hidden gems. As well as figuring out the differences between two text files, it can also report on the differences between whole directory trees.

Suppose you have just extracted the snapshot as explained above. Try running:

```
$ diff etc-baseline etc
```

The report will tell you:

1. which files/folders are in common (ie have not changed since your system was built);
2. which files are only in `/etc-baseline` (ie have been removed from `/etc` since the baseline was established);
3. which files are only in `/etc` (ie have been added to `/etc` since the baseline was established); and
4. which files are in both directories and have changed, and summarise their differences.

The report may seem a bit "busy" at first but you will quickly realise that it is telling you *exactly* what you need to know when it comes to configuring a newly-built system to behave the same as an older system which has just emitted magic smoke.

<a name="tipsSymlinks"></a>
### symlinks - known weakness

When symlinks are encountered by `tar`, its default behaviour is to include the symlink "as is" rather than follow the link to the file system objects to which it points (dereferencing).

This behaviour can be overridden with the `-h` option but that appears to result in the snapshot failing to unpack without `sudo`. That's problematic because it implies an attempt to re-establish the "same" relationships on the recovery system. That is somewhere between *inappropriate* and *dangerous.*

> In case it isn't crystal clear: **don't** use `sudo` to unpack a snapshot!

There may be a way to resolve this but, for now, the script avoids the problem by accepting the default behaviour. What this means is that some files which you would normally expect to find in `/etc` will not be present in the snapshot. At the time of writing, the files in this category were:

```
/etc/mtab
/etc/os-release
/etc/rmt
```

