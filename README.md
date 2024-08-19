
# Rusherhack plugin manager

Installs Rusherhack plugin for you and sets the needed flags.

feel free to make pr if you wanna add something

![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/kybe236/rhp/total?style=flat)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/kybe236/rhp)

## Disclaimer

be sure to open an github issue if you find any bugs.

pls use code kybe for rusherhack too support me

# Installation

## Install rhp

move downloaded file to your bin

## Build rhp from source

```bash
  zig build -Doptimize=ReleaseSafe
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
