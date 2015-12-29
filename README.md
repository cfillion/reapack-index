# Package indexer for ReaPack-based repositories

[https://github.com/cfillion/reapack](https://github.com/cfillion/reapack)

[![Build Status](https://travis-ci.org/cfillion/reapack-index.svg?branch=master)](https://travis-ci.org/cfillion/reapack-index)
[![Coverage Status](https://coveralls.io/repos/cfillion/reapack-index/badge.svg?branch=master&service=github)](https://coveralls.io/github/cfillion/reapack-index?branch=master)

### Installation

Ruby 2 need to be installed on your computer and ready to be used.
Install the dependencies with these commands:

```
cd path-to-this-repository
gem install bundler
bundle install
```

### Usage

```
bundle exec bin/reascript-indexer [options] [path-to-your-reascript-repository]
```

### Configuration

Various options can be used from the command line or stored in configuration files (one option per line):

```
Options:
    -a, --[no-]amend                 Reindex existing versions
    -o, --output FILE=./index.xml    Set the output path of the database
    -V, --[no-]verbose               Run verbosely
    -W, --warnings                   Enable all warnings
    -w, --no-warnings                Turn off warnings
    -v, --version                    Display version information
    -h, --help                       Prints this help
```

Options are read from these sources, in order (the last read options override any previous value):
- ~/.reapack-index.conf (`~` = home directory)
- ./.reapack-index.conf (`.` = current directory)
- command line

## Metadata Documentation

This indexer uses metadata found at the start of the files to generate the
database in ReaPack format.
See also [MetaHeader](https://github.com/cfillion/metaheader)'s documentation.

### Package Tags

These tags affects an entire package. Changes to any of those tags are
applied immediately and may affect released versions.

**@noindex**

Disable indexing for this file. Set this on included files that
should not be distributed alone.

```
@noindex

NoIndex: true
```

**@version** [required]

The current package version.
Value must contain between one and four groups of digits.

```
@version 1.0
@version 1.2pre3

Version: 0.2015.12.25
```

### Version Tags

These tags are specific to a single package version. You may still edit them
after a release by passing the `--amend` option to the indexer.

**@changelog**

```
@changelog
  Documented the metadata syntax
  Added support for deleted scripts

Changelog:
  Added an alternate syntax for metadata tags
```

**@provides**

Add additional files to the package.
These files will be installed/updated together with the package.

```
@provides unicode.dat

Provides:
  Images/background.png
  Images/fader_small.png
  Images/fader_big.png
```
