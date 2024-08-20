
# Rusherhack plugin manager

Installs Rusherhack plugin for you and sets the needed flags.

feel free to make pr if you wanna add something

![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/kybe236/rhp/total?style=flat)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/kybe236/rhp)

## Disclaimer

be sure to open an github issue if you find any bugs.

pls use code kybe for rusherhack too support me

# Installation

## Arch

#### With an AUR manager

```bash
paru -S rhp-git
```

```bash
yay rhp-git
```

#### Without an packet manager

```bash
git clone https://aur.archlinux.org/rhp-git.git && cd rhp-git && makepkg -si
```

## Every platform

move downloaded file to your bin

## Build rhp from source

```bash
  zig build -Doptimize=ReleaseFast
  mv zig-out/bin/rhp /usr/bin
```

# Usage

## Settings

### configuration wizard
```bash
rhp --config
```

### seting an specifig seting

### keys

- mc_path:  string
- cfg:  bool
- subnames: bool

```bash
rhp --config set <key> <value>
```

### Geting an setting

```bash
rhp --config get <key>
```

## Installing

to install an plugin

```bash
rhp <name>
```

to search with multiple words

```bash
rhp "<word> <word>"
```

# Usage developer

### Listen for file changes and change the mod in the mc folder

```bash
rhp --watch file
```

## How it works

It gets the contents of the [plugin list](https://github.com/RusherDevelopment/rusherhack-plugins) from [@Garlic](https://github.com/GarlicRot)

After that it first of splits anything betwen \<!-- START PLUGINS LIST --> and \<!-- END PLUGINS LIST -->

Then it splits by \---

The name and url for the downloads originate from the header (the on starting with \### [)

The description is based on whats left after ignoring every tag for images and vidios so if theres none of these and it isn't empty its the tag

Then it does some github site lookups.

1. https://github.com/user/repo/releases

from there it gets the tag url via the header 

2.  https://github.com/user/repo/releases/expanded_assets/tag-id

fom there it gets all releases and asks the user wich to download and then downloads it


