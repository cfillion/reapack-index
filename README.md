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
bundle exec bin/reascript-indexer <path-to-your-reascript-repository>
```

## Metadata Documentation

This indexer uses metadata found at the start of the files to generate the
database in ReaPack format.
See also [MetaHeader](https://github.com/cfillion/metaheader)'s documentation.

#### Required Tags

**@version** (value must contain between one and four groups of digits)

```
@version 1.0
@version 1.2pre3

Version: 0.2015.12.25
```

#### Optional Tags

**@changelog**

```
@changelog
  Documented the metadata syntax
  Added support for deleted scripts

Changelog:
  Added an alternate syntax for metadata tags
```

**@noindex**

Disable indexing for this file. Should be used on included files that cannot be
used alone.

```
@noindex

NoIndex: true
```

**@provides**

Add additional files to the package.

```
@provides unicode.dat

Provides:
  Images/background.png
  Images/fader_small.png
  Images/fader_big.png
```
