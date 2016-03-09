# Package indexer for ReaPack-based repositories

Parent project: [https://github.com/cfillion/reapack](https://github.com/cfillion/reapack)  
Subproject: [https://github.com/cfillion/metaheader](https://github.com/cfillion/metaheader)

[![Gem Version](https://badge.fury.io/rb/reapack-index.svg)](http://badge.fury.io/rb/reapack-index)
[![Build Status](https://travis-ci.org/cfillion/reapack-index.svg?branch=master)](https://travis-ci.org/cfillion/reapack-index)
[![Dependency Status](https://gemnasium.com/cfillion/reapack-index.svg)](https://gemnasium.com/cfillion/reapack-index)
[![Coverage Status](https://coveralls.io/repos/cfillion/reapack-index/badge.svg?branch=master&service=github)](https://coveralls.io/github/cfillion/reapack-index?branch=master)

### Installation

Ruby 2 need to be installed on your computer and ready to be used from a command
prompt. Run the following command from a command prompt (cmd.exe, Terminal.app,
XTerm) to install reapack-index on your computer:

```
gem install reapack-index
```

### Usage

```
reapack-index [options] [path-to-your-reascript-repository]
```

```
Options:
    -a, --[no-]amend                 Reindex existing versions
    -c, --check                      Test every package including uncommited changes and exit
    -i, --ignore PATH                Don't check or index any file starting with PATH
    -o, --output FILE=./index.xml    Set the output filename and path for the index
    -l, --link LINK                  Add or remove a website link
        --donation-link LINK         Add or remove a donation link
        --ls-links                   Display the link list then exit
    -A, --about=FILE                 Set the about content from a file
        --remove-about               Remove the about content from the index
        --dump-about                 Dump the raw about content in RTF and exit
        --[no-]progress              Enable or disable progress information
    -V, --[no-]verbose               Activate diagnosis messages
    -C, --[no-]commit                Select whether to commit the modified index
        --prompt-commit              Ask at runtime whether to commit the index
    -W, --warnings                   Enable warnings
    -w, --no-warnings                Turn off warnings
    -q, --[no-]quiet                 Disable almost all output
        --no-config                  Bypass the configuration files
    -v, --version                    Display version information
    -h, --help                       Prints this help
```

### Configuration

Options can be specified from the command line or stored in configuration files.
The syntax is the same as the command line, but with a single option per line.

The settings are applied in the following order:

- ~/.reapack-index.conf (`~` = home directory)
- ./.reapack-index.conf (`.` = repository root)
- command line

## Packaging Documentation

This indexer uses metadata found at the start of the files to generate the
database in ReaPack format.
See also [MetaHeader](https://github.com/cfillion/metaheader)'s documentation.

Tag not explicitly marked as required are optional.

### Package type by extension:

- `.lua`, `.eel`, `.py`: ReaScripts – the package file itself will be used as a source.
- `.ext`: For REAPER native extensions

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
after a release by running the indexer with the `--amend` option.

**@author**

```
@author cfillion

Author: Christian Fillion
```

**@changelog**

```
@changelog
  Documented the metadata syntax
  Added support for deleted scripts

Changelog:
  Added an alternate syntax for metadata tags
```

**@provides**

Add additional files to the package. This is also used to add platform restrictions
or set a custom download url (by default the download url is based on the "origin"
git remote).  These files will be installed/updated together with the package.

```
@provides unicode.dat

Provides:
  Images/background.png
  Images/fader_small.png
  Images/fader_big.png

@provides
  [windows] reaper_extension.dll http://mysite.com/download/$version/$path
```

List of supported platform strings:
- `windows`: All versions of Windows
- `win32`: Windows 32-bit
- `win64`: Windows 64-bit
- `darwin`: All versions of OS X
- `darwin32`: OS X 32-bit
- `darwin64`: OS X 64-bit

The following variables will be interpolated if found in the URL:
- `$path`: The path of the file relative to the package
- `$commit`: The hash of the commit being indexed or "master" if unavailable
- `$version`: The version of the package being indexed

Platform restriction and custom url can be set for the package itself,
either by using its file name or a dot:

```
-- this is a lua script named `hello_osx.lua`
-- @provides
--   [darwin] hello_osx.lua

-- @provides
--   [darwin] .
```
