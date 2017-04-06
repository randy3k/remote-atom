# remote-atom

Remote Atom is a package for Atom which implements the Textmate's 'rmate'
feature for Atom. It transfers files to be edited from remote server using SSH
port forward and transfers the files back when they are saved.

If you like it, you could send me some tips via [paypal](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=YAPVT8VB6RR9C&lc=US&item_name=tips&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donateCC_LG%2egif%3aNonHosted) or [gratipay](https://gratipay.com/~randy3k/).


# Installation
Remote Atom can easily be installed using the Atom package manager by going to "Settings > Install" and searching for remote-atom, or by using the command line:

```
sudo apm install remote-atom
```

On the remote server, we need to install [rmate](https://github.com/aurora/rmate) (this one is the bash version). You don't have to install it if you have been using `rmate` with TextMate or Sublime Text.
It is the same executable for TextMate and Sublime Text. If not, it (the bash version) can be installed by running this script (assume that you have the permission),

```bash
curl -o /usr/local/bin/rmate https://raw.githubusercontent.com/aurora/rmate/master/rmate
sudo chmod +x /usr/local/bin/rmate
```

You can also rename the command to `ratom`

```
mv /usr/local/bin/rmate /usr/local/bin/ratom
```

If your remote system does not have `bash` (so what else does it have?), there are different versions of `rmate` to choose from:

- The official ruby version: https://github.com/textmate/rmate
- A bash version: https://github.com/aurora/rmate
- A perl version: https://github.com/davidolrik/rmate-perl
- A python version: https://github.com/sclukey/rmate-python
- A nim version: https://github.com/aurora/rmate-nim
- A C version: https://github.com/hanklords/rmate.c
- A node.js version: https://github.com/jrnewell/jmate

# Usage

Open your Atom application, go to the menu `Packages -> Remote Atom`,
and click `Start Server`. Your can also launch the server via command palette.
The server can also be configured to be launched at startup in the preference.

Then, open an ssh connection to the remote server with remote port forwarded.
It can be done by

```bash
ssh -R 52698:localhost:52698 user@example.com
```

After running the server, you can just open the file on the remote system by

```
rmate test.txt
```
... or if you renamed it to `ratom` then ...

```
ratom test.txt
```

If everything has been setup correctly, your should be able to see the opening file in Atom.

### SSH config
It could be tedious to type `-R 52698:localhost:52698` everytime you ssh. To make your
life easier, add the following to `~/.ssh/config`,

```
Host example.com
    RemoteForward 52698 localhost:52698
    User user
```

From now on, you only have to do `ssh example.com`.

### Known issues
Since each window of Atom is a separate instance, the tcp server can only be running
on one window. Therefore, file will only be opened in the window with the server running.
If that window is closed, the server can be restarted by clicking
`Packages -> Remote Atom -> Start Server`.


# TODO
- writing tests
