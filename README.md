# Jakka

A minimalist and portable JSON transformer inspired by `jq` written in POSIX `awk`.

## Installation

Copy `jakka.awk` and `jakka` files to your binary directory of choice - e.g. `~/.local/bin` - that resides in your `PATH` environment variable.

## Usage

```bash
$ echo '"foo"' | jakka . # identity operator
"foo"
$ echo '"foo\tbar"' | jakka unwrap # unwrap JSON strings into ordinary strings
foo	bar
$ echo '["foo","bar"]' | jakka .[1] # array subscript
"bar"
$ echo '{"foo":"bar"}' | jakka .foo # object field access
"bar"
```

## Tests

```bash
$ bashunit ./jakka_test.sh
```
