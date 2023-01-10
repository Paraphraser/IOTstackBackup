# Tutorial: Generating GnuPG Keys

Snapshot encryption is completely optional. You do not have to encrypt your snapshots unless you want to.

This guide will help you generate a GnuPG key-pair so you can encrypt your snapshots. Generation is done in a non-destructive manner. It will **not** affect any existing keychains you might have. The end product of this guide is ASCII text files containing matching public and private keys. The keys will only go into effect when you import them on the systems where you need to use them.  

You don't need to create encryption keys just for IOTstackBackup. If you already have one or more GnuPG key-pairs with encryption/decryption capabilities, feel free to re-use those keys. The reverse is also true. Just because you created a key-pair for encrypting snapshots doesn't mean you can't re-use those keys for encrypting other files. 

There are many guides about this topic on the web so, if you prefer to follow a different guide, you can do that. One example is the excellent [Dr Duh](https://github.com/drduh/YubiKey-Guide) guide which will walk you through the process of creating GnuPG keys on a YubiKey.

> Acknowledgement: many ideas are drawn from the [Dr Duh](https://github.com/drduh/YubiKey-Guide) guide.

## Contents

- [Prerequisites](#prerequistes)
- [Generating a key-pair](#keyPairGeneration)

	- [Step 1 – Setup](#keyPairGenSetup)
	- [Step 2 – Key generation](#keyPairKeyGen)
	- [Step 3 – Key export](#keyPairGenExport)
	- [Step 4 – Tear-down](#keyPairGenTeardown)

- [Using your public key](#usePublic)

	- [Installing your public key](#installPublic)
	- [Trusting your public key](#trustPublic)
	- [Your public key in action](#actionPublic)

- [Using your private key](#usePrivate)

	- [Installing your private key](#installPrivate)
	- [Trusting your keys](#trustPrivate)
	- [Your private key in action](#actionPrivate)

<a name="prerequistes"></a>
## Prerequisites

This guide assumes:

1. You are working on a Raspberry Pi (or Debian system).
2. You have installed the `gnupg2` package and any necessary supporting tools.

If you used [PiBuilder](https://github.com/Paraphraser/PiBuilder) to build your operating system:

- All required components are already installed; and
- Your Pi is also *"[Dr Duh](https://github.com/drduh/YubiKey-Guide) ready".*

The [Dr Duh](https://github.com/drduh/YubiKey-Guide) guide explains how to install GnuPG and related tools on other platforms such as macOS and Windows.

<a name="keyPairGeneration"></a>
## Generating a key-pair

<a name="keyPairGenSetup"></a>
### Step 1 – Setup

Execute the following commands on your Raspberry Pi:

```
$ RAMDISK="/run/user/$(id -u)/ramdisk" ; mkdir -p "$RAMDISK"
$ sudo mount -t tmpfs -o size=128M myramdisk "$RAMDISK"
$ sudo chown $USER:$USER "$RAMDISK"; chmod 700 "$RAMDISK"
$ export GNUPGHOME=$(mktemp -d -p "$RAMDISK"); echo "GNUPGHOME = $GNUPGHOME"
$ cd "$GNUPGHOME"
```

In words:

1. Construct a mount-point for a RAM disk.
2. Create and mount a 128MB RAM disk at that mount-point.
3. Assign RAM disk ownership and permissions to the current user.
4. Make a temporary working directory for GnuPG operations in the RAM disk. This disconnects the current login session from the default of `~/.gnupg` and means all operations will fail safe.
5. Make the temporary working directory the current working directory.

By its very nature, a RAM disk is ephemeral. It will disappear as soon as you reboot your Pi or complete the [tear-down](#keyPairGenTeardown) steps. It is also an isolated environment which is inherently forgiving of any mistakes. You can experiment freely without worrying about breaking anything.

<a name="keyPairKeyGen"></a>
### Step 2 – Key generation

Although it isn't mandatory, you should always protect any private key with a passphrase. You can use any scheme you like but one good approach is to let GnuPG generate some random gibberish for you:

```
$ PASSPHRASE=$(gpg --gen-random --armor 0 24)
$ echo $PASSPHRASE
```

You will need to provide your passphrase each time you need to either manipulate your private key or decrypt a file that is encrypted with the corresponding public key. If you forget your passphrase, your private key will be lost, your public key useless, and you will not be able to decrypt your files.

> If you follow the [Dr Duh](https://github.com/drduh/YubiKey-Guide) and your private keys are stored on a YubiKey, you will need to enter the key's PIN and then touch the key to approve each decryption operation. 

Once you have decided on your passphrase, use the following as a template:

```
gpg --batch --quick-generate-key "«given» «last» («comment») <«email»>" rsa4096 encrypt never
```

Replace:

* `«given»` and `«last»` with your name
* `«comment»` with something reflecting the purpose of the key-pair; and
* `«email»` with an RFC821 "mailbox@domain" email address.

None of the fields needs to be truthful. The email address does not have to exist. Example:

```
$ gpg --batch --quick-generate-key "Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>" rsa4096 encrypt never
```

You will be prompted for your passphrase. If you decide you do **not** want to use a passphrase, respond to the prompt by pressing <kbd>tab</kbd> to select `<OK>`, then press <kbd>return</kbd>, and then confirm your decision by pressing <kbd>return</kbd> again. Without the protection of a passphrase, anyone with access to your private key will be able to decrypt any file encrypted with the corresponding public key.

There will be a small delay and you will see a result like the following:

```
gpg: keybox '/run/user/1000/ramdisk/tmp.iqcUsUYgRU/pubring.kbx' created
gpg: /run/user/1000/ramdisk/tmp.iqcUsUYgRU/trustdb.gpg: trustdb created
gpg: key 88F86CF116522378 marked as ultimately trusted
gpg: directory '/run/user/1000/ramdisk/tmp.iqcUsUYgRU/openpgp-revocs.d' created
gpg: revocation certificate stored as '/run/user/1000/ramdisk/tmp.iqcUsUYgRU/openpgp-revocs.d/CE90947C208A2B994B1ED48988F86CF116522378.rev'
```

In the above output, the 3<sup>rd</sup> line is:

```
gpg: key 88F86CF116522378 marked as ultimately trusted
```

The string `88F86CF116522378` is the keyID of this key-pair. Find the same line in your output and associate your keyID with the `GPGKEYID` environment variable, like this:

```
$ export GPGKEYID=88F86CF116522378
```

Make a note of this command because you will need both it and the keyID again.

<a name="keyPairGenExport"></a>
### Step 3 – Key export

At this point, your newly-generated keys are stored in a keychain in the RAM disk. You need to export them:

```
$ gpg --export-secret-keys --armor "$GPGKEYID" >"$HOME/$GPGKEYID.gpg.private.key.asc"
$ gpg --export --armor "$GPGKEYID" >"$HOME/$GPGKEYID.gpg.public.key.asc"
```

> If you set a passphrase, you will have to supply it for the first command.

The files exported to your home directory are just plain ASCII text. You can list their contents like this:

```
$ cat "$HOME/$GPGKEYID.gpg.private.key.asc"
$ cat "$HOME/$GPGKEYID.gpg.public.key.asc"
```

<a name="keyPairGenTeardown"></a>
### Step 4 – Tear-down

Run the following commands:

```
$ cd
$ sudo umount "$RAMDISK"
$ rmdir "$RAMDISK"
$ unset GNUPGHOME
```

In words:

1. Move to your home directory.
2. Un-mount the RAM disk.
3. Delete the mount-point for the RAM disk.
4. Clear the GNUPGHOME variable, which means the default of `~/.gnupg` is now back in effect.

Thus far, other than the ASCII text files containing your exported keys, no command has had a persistent effect. If you are unsure of any decisions you have made (eg whether or not to use a passphrase), you can simply start over from [Setup](#keyPairGenSetup).

<a name="usePublic"></a>
## Using your public key

Your *public* key is used for encryption. That means it needs to be installed on every machine where you may wish to encrypt a snapshot.

<a name="installPublic"></a>
### Installing your public key

Replace `88F86CF116522378` with your own keyID then execute the command:

```
$ export GPGKEYID=88F86CF116522378
```

The following command assumes the file containing your public key is in your working directory (ie a simple `ls` command will show it):

```
$ gpg --import "$GPGKEYID.gpg.public.key.asc"
gpg: key 88F86CF116522378: public key "Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>" imported
gpg: Total number processed: 1
gpg:               imported: 1
```

<a name="trustPublic"></a>
### Trusting your public key

If you list your public keys, you will see that the key is untrusted:

```
$ gpg -k
/home/pi/.gnupg/pubring.kbx
---------------------------
pub   rsa4096 2023-01-03 [CE]
      CE90947C208A2B994B1ED48988F86CF116522378
uid           [ unknown] Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>
```

The "unknown" indicates that the key is not trusted. You should fix that by running the following commands:

```
$ gpg --edit-key "$GPGKEYID"
gpg> trust
Your decision? 5
Do you really want to set this key to ultimate trust? (y/N) y
gpg> quit
$
```

You can confirm that the key is trusted by listing your public keys again:

```
$ gpg -k
/home/pi/.gnupg/pubring.kbx
---------------------------
pub   rsa4096 2023-01-03 [CE]
      CE90947C208A2B994B1ED48988F86CF116522378
uid           [ultimate] Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>
```

If you do not mark your public key as trusted, `gpg` will ask for permission to use the public key each time you attempt to use it to encrypt a file.

<a name="actionPublic"></a>
### Your public key in action

Create a test file. Something like this:

```
$ ls -l >plaintext.txt
```

To encrypt that file:

```
$ gpg --recipient "$GPGKEYID" --output "plaintext.txt.gpg" --encrypt "plaintext.txt" 
```

<a name="usePrivate"></a>
## Using your private key

Your *private* key is used for decryption. That means it only needs to be installed on machines where you intend to decrypt snapshots.

<a name="installPrivate"></a>
### Installing your private key

You will need to copy the ASCII file containing your private key onto any machine where you intend to decrypt your backups. How you do that is up to you (eg USB drive, scp, sshfs).

Anyone with possession of your private key and your passphrase (assuming you set one) will be able to decrypt your backups. You should keep this in mind as you decide how to copy the ASCII file containing your private key from machine to machine.

Similarly, if you lose your private key and don't have a backup of the ASCII file containing your private key from which you can re-import the private key, you will lose access to your backups.

Replace `88F86CF116522378` with your own keyID then execute the command:

```
$ export GPGKEYID=88F86CF116522378
```

The following command assumes the file containing your public key is in your working directory (ie a simple `ls` command will show it):

```
$ gpg --import "$GPGKEYID.gpg.private.key.asc"
gpg: key 0x88F86CF116522378: public key "Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>" imported
Please enter the passphrase to import the OpenPGP secret key:
"Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>"
4096-bit RSA key, ID 0x88F86CF116522378,
created 2023-01-03.

Passphrase: 
gpg: key 0x88F86CF116522378: secret key imported
gpg: Total number processed: 1
gpg:               imported: 1
gpg:       secret keys read: 1
gpg:   secret keys imported: 1
```

Your private key also contains your public key so this process imports both keys. To list your public key, use the lower-case `-k` option (which is a synonym for the `--list-keys` option):

```
$ gpg -k
pub   rsa4096/0x88F86CF116522378 2023-01-03 [CE]
      Key fingerprint = CE90 947C 208A 2B99 4B1E  D489 88F8 6CF1 1652 2378
uid                   [ unknown] Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>
```

To list your private key, use the upper-case `-K` option (which is a synonym for the `--list-secret-keys` option):

```
$ gpg -K
sec   rsa4096/0x88F86CF116522378 2023-01-03 [CE]
      Key fingerprint = CE90 947C 208A 2B99 4B1E  D489 88F8 6CF1 1652 2378
uid                   [ unknown] Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>
```

The only difference between the two is the "pub" vs "sec" in the first line.

<a name="trustPrivate"></a>
### Trusting your keys

In the output above, you may have noted the "unknown" trust status for the keys in your key-pair. You can fix that in the same way as you did when you imported your public key:

```
$ gpg --edit-key "$GPGKEYID"
gpg> trust
Your decision? 5
Do you really want to set this key to ultimate trust? (y/N) y
gpg> quit
$
```

<a name="actionPrivate"></a>
## Your private key in action

Assuming the file you encrypted earlier is available on the system where you installed your private key, you can decrypt that file like this:

```
$ gpg --output "restored.txt" --decrypt "plaintext.txt.gpg"

gpg: encrypted with rsa4096 key, ID 0x88F86CF116522378, created 2023-01-03
      "Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>"
Please enter the passphrase to unlock the OpenPGP secret key:
"Roger Rabbit (Raspberry Pi Backups) <chewie@carrots.com>"
4096-bit RSA key, ID 0x88F86CF116522378,
created 2023-01-03.

Passphrase: 
```

Notes:

1. If you set a passphrase, you will have to supply it at the prompt.
2. The GPGKEYID environment variable does not have to be set for decryption (`gpg` figures that out for itself).

Assuming successful decryption, the result will be the file `restored.txt`, which you can compare with the original `plaintext.txt` to assure yourself that the round-trip has maintained fidelity.

Whenever you are decrypting a file, always think about where to store the result. Suppose you are working on a macOS or Windows system where the encrypted snapshots are stored in your Dropbox scope. If you decrypt into the same directory, Dropbox will sync the decrypted file so you will have lost the protection afforded by encryption. It would be more appropriate to either move (or copy) the encrypted snapshot out of the Dropbox scope or adjust the `--output` path to point to a destination outside of the Dropbox scope.
