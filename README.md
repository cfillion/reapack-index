# Package indexer for ReaPack-based repositories

[https://github.com/cfillion/reapack](https://github.com/cfillion/reapack)

[![Build Status](https://travis-ci.org/cfillion/reapack-index.svg?branch=master)](https://travis-ci.org/cfillion/reapack-index)
[![Coverage Status](https://coveralls.io/repos/cfillion/reapack-index/badge.svg?branch=master&service=github)](https://coveralls.io/github/cfillion/reapack-index?branch=master)

# Metadata Documentation

This indexer uses metadata found at the start of the files to generate the
database in ReaPack format.

### Required Keys

**@author**

```
@author cfillion
```

**@version** (value must contain between one and four groups of digits)

```
@version 1.0
@version 1.2pre3
```

### Optional Keys

**@changelog**

```
@changelog
  Documented the metadata syntax
  Added support for deleted scripts
```
