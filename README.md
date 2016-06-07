# Package indexer for git-based ReaPack repositories

Parent project: [https://github.com/cfillion/reapack](https://github.com/cfillion/reapack)  
Subproject: [https://github.com/cfillion/metaheader](https://github.com/cfillion/metaheader)

[![Gem Version](https://badge.fury.io/rb/reapack-index.svg)](http://badge.fury.io/rb/reapack-index)
[![Build Status](https://travis-ci.org/cfillion/reapack-index.svg?branch=master)](https://travis-ci.org/cfillion/reapack-index)
[![Dependency Status](https://gemnasium.com/cfillion/reapack-index.svg)](https://gemnasium.com/cfillion/reapack-index)
[![Coverage Status](https://coveralls.io/repos/cfillion/reapack-index/badge.svg?branch=master&service=github)](https://coveralls.io/github/cfillion/reapack-index?branch=master)
[![Donate](https://www.paypalobjects.com/webstatic/en_US/btn/btn_donate_74x21.png)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=T3DEWBQJAV7WL&lc=CA&item_name=reapack-index%3a%20Package%20indexer%20for%20git-based%20ReaPack%20repositories&no_note=0&cn=Custom%20message&no_shipping=1&currency_code=CAD&bn=PP%2dDonationsBF%3abtn_donateCC_LG%2egif%3aNonHosted)

### Installation

Ruby v2.3 or newer must be installed on your computer in order to install
and use this software.  
Run the following command from a command prompt (eg. cmd.exe, Terminal.app,
XTerm) to install reapack-index:

```
gem install reapack-index
```

### Usage

```
reapack-index [options] [path-to-your-repository]
```

```
Modes:
    -c, --check                      Test every package including uncommited changes and exit
    -s, --scan [COMMIT]              Scan new commits (default) or specific commits
        --rebuild                    Clear the index and rescan the whole git history
Indexer options:
    -a, --[no-]amend                 Reindex existing versions
    -i, --ignore PATH                Don't check or index any file starting with PATH
    -U, --url-template TEMPLATE=auto Set the template for implicit download links
    -o, --output FILE=./index.xml    Set the output filename and path for the index
Repository metadata:
    -n, --name NAME                  Set the name shown in ReaPack for this repository
    -l, --link LINK                  Add or remove a website link
        --donation-link LINK         Add or remove a donation link
        --ls-links                   Display the link list then exit
    -A, --about=FILE                 Set the about content from a file
        --remove-about               Remove the about content from the index
        --dump-about                 Dump the raw about content in RTF and exit
Misc options:
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

A getting started guide and packaging documentation are available in
the [wiki](https://github.com/cfillion/reapack-index/wiki).

### Configuration

Options can be specified from the command line or stored in configuration files.
The syntax is the same as the command line, but with a single option per line.

The settings are applied in the following order:

- ~/.reapack-index.conf (`~` = home directory)
- ./.reapack-index.conf (`.` = repository root)
- command line
