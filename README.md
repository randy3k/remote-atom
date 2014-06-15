# remote-atom

Remote-atom is a package for Atom which implement the Textmate's 'rmate' feature for Atom.
It transfers files to be edited from remote server using SSH port forward and transfers the files back when they are saved.

# Installation
Remote-atom can be easily installed using the Atom package manager. On the remote server,
we need to install [rmate](https://github.com/aurora/rmate), it can be install by running this script

```bash
mkdir -p .local/bin
wget --no-check-certificate -O $HOME/.local/bin/rmate https://raw.github.com/aurora/rmate/master/rmate
```
Remember to export the PATH variable by adding

```bash
export PATH="$HOME/.local/bin:$PATH"
```
to your `.profile`.


### TODO
- writing tests