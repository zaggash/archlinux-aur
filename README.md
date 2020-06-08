![Drone (self-hosted) with branch](https://img.shields.io/drone/build/zaggash/archlinux-aur/master?label=build&logo=drone&server=https%3A%2F%2Fci.ziggzagg.fr&style=for-the-badge)  

## My Archlinux repo
This is an unofficial repository for Arch Linux.  
Originaly intended to fit my needs and build custom or unavailable packages.

### How to use it
- Trust my public key:
```
curl -sL 'https://keybase.io/apinon/pgp_keys.asc?fingerprint=54231a262e8bf5501c6945d275bcc090ca185c57' | sudo pacman-key -a -
pacman-key --lsign-key 54231a262e8bf5501c6945d275bcc090ca185c57
```

- Edit `/etc/pacman.conf` with:
```
[zaggarch-repo]
Server = https://$repo.sourceforge.io/$arch
SigLevel = Required
```

- Then update the DB:
```
pacman -Syy
```
