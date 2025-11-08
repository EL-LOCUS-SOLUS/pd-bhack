# `bhack` - the _b-side_ hack of the BACH library for Pd

`v0.0.0-alpha-0`

## About: 

This is a family of objects inspired by the BACH library for MAX, which deal with "llll" (lisp-like linked lists). In bhack, this are defined as regular Pd lists, with the list selector, but elements in brackets define nested lists in any depth.

It relies on [pdlua](https://github.com/EL-LOCUS-SOLUS/pd-lua) to manage this new data type and is supposed to be incorporated into the ELSE library (which carries pdlua and, teherefore, supports externals written in lua).

--------------------------------------------------------------------------
