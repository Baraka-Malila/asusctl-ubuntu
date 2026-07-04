# Launchpad PPA Setup

One-time setup for `ppa:malila/asusctl-ubuntu`. Do this once before the first
upload. All steps are on your local machine.

## 1. Create a Launchpad account

Go to https://launchpad.net and sign up. When asked for a username, enter:
`malila`

(Username is changeable before the first upload with zero cost to users.)

## 2. Create the PPA

After logging in, go to:
https://launchpad.net/~malila/+activate-ppa

Fill in:
- Name: `asusctl-ubuntu`
- Display name: ASUS Linux Ubuntu
- Description: Ubuntu packaging for asusctl + supergfxctl

## 3. Generate a GPG key

```bash
gpg --full-gen-key
```

At the prompts:
- Key type: RSA and RSA (option 1)
- Key size: 4096
- Expiry: 0 (does not expire)
- Real name: Baraka Malila
- Email: bmalila87@gmail.com
- Comment: (leave blank, press Enter)
- Passphrase: choose a strong one

## 4. Upload your key to Ubuntu's keyserver

```bash
# Find your key ID (the long hex string after rsa4096/)
gpg --list-secret-keys --keyid-format LONG bmalila87@gmail.com
# Example output:
# sec   rsa4096/ABCD1234EFGH5678 2026-07-03 [SC]

# Upload (replace with your actual key ID)
gpg --keyserver keyserver.ubuntu.com --send-keys ABCD1234EFGH5678
```

## 5. Register the key in Launchpad

Get your key fingerprint:
```bash
gpg --fingerprint bmalila87@gmail.com
```

Copy the fingerprint (40 hex chars with spaces, like
`XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX`).

Go to: https://launchpad.net/~malila/+editpgpkeys
Paste the fingerprint and click "Import Key".

Launchpad emails `bmalila87@gmail.com` with an encrypted confirmation message.
Decrypt it to get the confirmation link:
```bash
# Paste the encrypted block (everything between ---BEGIN and ---END), then Ctrl+D
gpg --decrypt
```

Click the link in the decrypted output to confirm.

## 6. Install upload tools

```bash
sudo apt-get install -y devscripts dput
```

## 7. Verify setup

```bash
gpg --list-secret-keys bmalila87@gmail.com   # should list your key
dput --version                                # should print a version number
```

## Uploading packages (per release)

CI must be green on main before uploading.

```bash
cd /home/cyberpunk/asus

# Upload all packages for jammy
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/upload-ppa.sh "$pkg" jammy
done

# Upload all packages for noble
for pkg in asus-backlight-fix asusctl supergfxctl asusctl-suite; do
    bash scripts/upload-ppa.sh "$pkg" noble
done
```

Launchpad emails `bmalila87@gmail.com` when each build completes (~10–20 min).
If a build fails, the email contains the build log URL.

## Releasing a new upstream version

1. Update `UPSTREAM_TAG` and `TARBALL_URL` in `packages/<pkg>/upstream.env`
2. Delete the cached `.orig.tar.xz`: `rm packages/<pkg>/build/<pkg>_*.orig.tar.xz`
3. Add a new changelog entry: `dch -v <new-version>~jammy1 "Update to <version>"`
4. Ensure CI is green
5. Run `upload-ppa.sh` for each package × each distro

Launchpad versions must be strictly increasing: `6.3.9-1~jammy1` > `6.3.8-1~jammy1`.
