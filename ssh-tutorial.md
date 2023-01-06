# Tutorial: Setting up SSH keys for password-less access

## Background

Security professionals (people whose dreams occur in a world filled with acronym soup which they never bother to explain to anyone) refer to the process described here as "TOFU", which means "Trust On First Use". TOFU is not considered a polite term.

Security professionals recommend setting up certificates. It's a laudable recommendation. In the long term, certificates are indeed worth the price of the very steep learning curve, particularly once you have more than a handful of hosts to worry about. Certificates are also "more secure", although what constitutes "sufficient" security in the average home environment is open to debate.

The learning-curve is the problem. If I started to explain the process of setting up certificates, I doubt you'd keep reading.

This tutorial is already long enough! And this is the *simple* approach.

## Task Goal

Set up two computers so that they can communicate with each other, securely, over SSH, without needing passwords.

## The actors

I'm going to use two Raspberry Pis but the same concepts apply if you are using desktop machines running Linux, macOS or Windows.

### First Raspberry Pi

|Variable    | Value         |
|------------|---------------|
|Host Name   | sec-dev       |
|Domain Name | sec-dev.local |
|User Name   | secuser       |

### Second Raspberry Pi

|Variable    | Value         |
|------------|---------------|
|Host Name   | tri-dev       |
|Domain Name | tri-dev.local |
|User Name   | triuser       |

I'm using Multicast DNS names (the things ending in `.local`; sometimes known as "ZeroConf", "Bonjour" or "Rendezvous" names) but you can substitute domain names or IP addresses if you wish.

## Assumption

I'm going to assume that both computers have SSH running. The simplest way to get SSH running on a Raspberry Pi is to create a file named `ssh` on the `/boot` volume, and reboot. If your RPi is connected to a keyboard and screen, open a terminal session and type:

```
$ sudo touch /boot/ssh
$ sudo reboot
```
	
Alternatively, temporarily move the SD card (or SSD if you are booting and running from SSD) to a desktop machine and create a file called "ssh" in the boot partition. Only the **name** of the file is important. Its contents are irrelevant.

## Login checks

### First login

Make sure that you can already login to each machine, albeit using passwords. Specifically:

1. On sec-dev:
	
	```
	$ ssh triuser@tri-dev.local
	
	The authenticity of host 'tri-dev.local (192.168.203.7)' can't be established.
	ED25519 key fingerprint is SHA256:a8e73b2ba4f2f183c3a90a9911817d6ece4eb3d45fd.
	Are you sure you want to continue connecting (yes/no)? yes
	Warning: Permanently added 'tri-dev.local,192.168.203.7' (ED25519) to the list of known hosts.
	triuser@ tri-dev.local's password: ••••••••
	Linux tri-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$ 
	```

2. On tri-dev:
	
	```
	$ ssh secuser@sec-dev.local
	
	The authenticity of host 'sec-dev.local (192.168.203.9)' can't be established.
	ED25519 key fingerprint is SHA256: 16befc20e7b13a52361e60698fa1742dcb41bb52331.
	Are you sure you want to continue connecting (yes/no)? yes
	Warning: Permanently added 'sec-dev.local,192.168.203.9' (ED25519) to the list of known hosts.
	secuser@sec-dev.local's password: ••••••••
	Linux sec-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$ 
	```
	
3. On **both** machines, logout (either Control+D or `exit`).

Everything from "The authenticity of …" down to "Warning: …" is **this** Raspberry Pi telling you that it doesn't know about the **other** Raspberry Pi.

This is the *Trust On First Use* pattern in action. Once you type "yes", each Raspberry Pi will remember (trust) the other one.

### Subsequent logins

1. On sec-dev:
	
	```
	$ ssh triuser@tri-dev.local
	
	triuser@tri-dev.local's password: ••••••••
	Linux tri-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$ 
	```

2. On tri-dev:
	
	```
	$ ssh secuser@sec-dev.local
	
	secuser@sec-dev.local's password: ••••••••
	Linux sec-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$ 
	```

3. On **both** machines, logout (either Control+D or `exit`).

This time, each Raspberry Pi already knows about the other so it bypasses the TOFU warnings and goes straight to asking you for the password.

But our goal is password-less access so let's keep moving.

## Generate user key-pairs

1. On sec-dev:

	```
	$ ssh-keygen -t rsa -C "secuser@sec-dev rsa key"
	```
	
	Notes:
	
	* I am specifying "rsa" because it is likely to be supported on any computers you are trying to use, pretty much regardless of age. It is also usually what you get by default if you omit the `-t rsa`. If you wish to use a more up-to-date algorithm, you can replace "rsa" with "ed25519". However, that will change some filenames and make these instructions more difficult to follow. You will also need to make sure that ED25519 is supported on all the systems where you want to use it.
	* the `-C "secuser@sec-dev rsa key"` is a comment which becomes part of the key files to help you identify which keys belong to what.

	ssh-keygen will ask some questions. Accept all the defaults by pressing return:

	```
	Generating public/private rsa key pair.
	Enter file in which to save the key (/home/secuser/.ssh/id_rsa): 
	Enter passphrase (empty for no passphrase): 
	Enter same passphrase again: 
	```
	
	You will then see output similar to this:
	
	``` 
	Your identification has been saved in /home/secuser/.ssh/id_rsa.
	Your public key has been saved in /home/secuser/.ssh/id_rsa.pub.
	The key fingerprint is:
	SHA256:NugXeay77qdVHYjvuaNg/HP3o6VdUWYdffZiWtT4xEY secuser@sec-dev rsa key
	The key's randomart image is:
	+---[RSA 2048]----+
	|               *E|
	|           . .o @|
	|          . ...=B|
	|       . o . .+++|
	|      . S o o+.o |
	|     . o = o..  .|
	|      . * . o  ..|
	|       o =o o.=..|
	|       o*+o+.=.oo|
	+----[SHA256]-----+
	```

2. On tri-dev:

	```
	$ ssh-keygen -t rsa -C "triuser rsa key"
	```
	
	and accept all the defaults, as above.

## Exchange public keys

1. On sec-dev:

	```
	$ ssh-copy-id -i ~/.ssh/id_rsa.pub triuser@tri-dev.local
	```
	
	The expected response looks like this:
	
	```
	/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/secuser/.ssh/id_rsa.pub"
	/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
	/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
	triuser@tri-dev.local's password: ••••••••
	
	Number of key(s) added: 1
	
	Now try logging into the machine, with:   "ssh 'triuser@tri-dev.local'"
	and check to make sure that only the key(s) you wanted were added.
	```
	
	Follow the advice and try logging-in:
	
	```
	$ ssh triuser@tri-dev.local
	Linux tri-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$
	```
	
	Like magic! No password prompt.

2. On tri-dev:

	```
	$ ssh-copy-id -i ~/.ssh/id_rsa.pub secuser@sec-dev.local
	```
	
	You should get a password prompt and, if you then try logging in:
	
	```
	$ ssh secuser@sec-dev.local
	Linux sec-dev 5.4.83-v7l+ #1379 SMP Mon Dec 14 13:11:54 GMT 2020 armv7l
	…
	$ 
	```  

	Double magic!

3. On **both** machines, logout (either Control+D or `exit`).

## What's stored where

On each machine, the `~/.ssh` directory will contain four files:

* `id_rsa` the private key for **this** user on **this** machine. This was set up by `ssh-keygen`.
* `id_rsa.pub` the public key matching the private key. This was set up by `ssh-keygen`.
* `known_hosts` a list of public keys for the **other** hosts **this** user account knows about. These keys are set up by the TOFU pattern.
* `authorized_keys` a list of public keys for the **users** that **this** user account is authorised to access without a password. These keys are set up by `ssh-copy-id`.

All of these files are "printable" in the sense that you can do:

```
$ cat ~/.ssh/*
```

### private keys

Security professionals like to tell you that a private key should never leave the computer on which it is generated. But, fairly obviously, you will want to make sure it is included in backups. If you don't then you will have to go through this process again. Unless you're paranoid, somewhat more reasonable advice is to "treat your private key like your wallet and don't leave it lying around."

### known_hosts

On some implementations, the information in `known_hosts` is hashed to make it unreadable. This is the case on the Raspberry Pi.

Suppose you rebuild tri-dev starting from a clean copy of Raspbian. On first boot, the operating system will generate new host keys (the host equivalent of `ssh-keygen` to generate user key-pairs). Those are stored in `/etc/ssh`.

When you try logging-in from sec-dev, you'll get a warning about how some other computer might be trying to impersonate the computer you are actually trying to reach. What the warning **actually** means is that the entry for tri-dev in your `known_hosts` file on sec-dev doesn't match the keys that were generated when tri-dev was rebuilt.

To solve this problem, you just remove the offending key from your known-hosts file. For example, to make sec-dev forget about tri-dev:

```
$ ssh-keygen -R tri-dev.local
```

Then you can try to connect. You'll get the TOFU warning as sec-dev learns tri-dev's new identity, after which everything will be back to normal.

### authorized_keys

This is just a text file with one line for each host that has sent its public key to **this** host via `ssh-copy-id`.

When you add a new host to your network, it can become a bit of a pain to have to run around and exchange all the keys. It's a "full mesh" or n<sup>2</sup> problem, and one that "certificates" avoid.

There is, however, no reason why you can't maintain a single authoritative list of all of your public keys which you update once, then push to all of your machines (ie reduce the n<sup>2</sup> problem to an n problem).

Suppose you decide that sec-dev will be the authoritative copy of your authorized_keys file. It already holds the public key for tri-dev. It simply needs its own public key added:

```
$ cd ~/.ssh
$ cat id_rsa.pub >>authorized_keys
```

Then you can push that file to tri-dev:

```
$ scp authorized_keys triuser@tri-dev.local:~/.ssh
```

Suppose you add a new Raspberry Pi called "quad-dev". You've reached the point where you've used `ssh-copy-id` to transfer quad-dev's public key to sec-dev, so it's now in sec-dev's authorized_keys file. All you need to do is to go to sec-dev and:

```
$ scp authorized_keys triuser@tri-dev.local:~/.ssh
$ scp authorized_keys quaduser@quad-dev.local:~/.ssh
```

> You'll still face the one-time TOFU pattern on each host that hasn't previously connected to quad-dev.

### ~/.ssh/config

One file we haven't mentioned is the config file. This is the basic pattern:

```
host sec-dev
  hostname sec-dev.local
  user secuser

host tri-dev
  hostname tri-dev.local
  user triuser
```

With that file in place on both sec-dev and tri-dev:

1. On sec-dev, you can login to tri-dev with just:

	```
	$ ssh tri-dev
	```
	
2. On tri-dev, you can login to sec-dev with just:

	```
	$ ssh sec-dev
	```
	
What's happening is that SSH is matching on the name in the "host" field, replacing it with the value of the "hostname" field, and sticking the value of the "user" field on the front.

If any of your computers is running macOS High Sierra or later, also add this line after each "user" field:

```
  UseKeychain yes
```

You can't necessarily put "UseKeychain no" on non-macOS systems because the configuration file parser may not recognise the directive. A better approach is to maintain a master copy which includes the "UseKeychain yes" directives, use that file "as is" on macOS, but filter it for systems that don't support the directive. For example:

* On a macOS system (as-is):

	```
	$ cp ssh_config_master ~/.ssh/config
	```

* On other systems (filter):

	```
	$ grep -v "UseKeychain" ssh_config_master >~/.ssh/config
	```
