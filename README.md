# `bhack` - the _b-side_ hack of the BACH library for Pd

`v0.0.0-alpha-0`

## About: 

This is a family of objects inspired by the BACH library for MAX, which deals with "llll" (lisp-like linked lists). In bhack, these are defined as a more powerful dictionary data type, so called 'dddd' ("Dictionary Driven Data Design" or simply a "Damn Dictionary Data Deal"). This data type is also represented in Pd as regular Pd lists - with the list selector and all - but elements in brackets define nesting.

This project relies on [pdlua](https://github.com/EL-LOCUS-SOLUS/pd-lua) to manage this new data type and is supposed to be incorporated into the ELSE library as soon as it is kinda ready. Note that ELSE carries pdlua and, therefore, supports externals written in lua.

--------------------------------------------------------------------------
