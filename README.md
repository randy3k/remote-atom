# remote-atom

Remote-atom is a package for Atom which implement the Textmate's 'rmate' feature for Atom.
It transfers files to be edited from remote server using SSH port forward and transfers the files back when they are saved.

# Installation
Remote-atom can be easily installed using the Atom package manager. On the remote server,
we need to install [rmate](https://github.com/aurora/rmate).
It is the same executable for TextMate and Sublime Text. You don't have to install it
if your Textmate/Sublime Text alternatives are working. If not,
it can be install by running this script

```bash
mkdir -p .local/bin
wget --no-check-certificate -O $HOME/.local/bin/rmate https://raw.github.com/aurora/rmate/master/rmate
```
Remember to export the PATH variable by adding

```bash
export PATH="$HOME/.local/bin:$PATH"
```
to your `.profile`.

# Usage
You have to first open an ssh connection to the remote server. In addition, you have
to foward to remote port. It can be done by

```bash
ssh -R 52698:localhost:52698 user@example.com
```

If you are logged in on the remote system, you can now just execute

```
rmate test.txt
```

### TODO
- writing tests

### Known issues
Since each window of Atom is a separate instance, the tcp server can only be started
on the first window. Therefore, file will only be opened in the first window. If
the first window is closed, the package has to be reactivated by disabling and reenabling
it.  
