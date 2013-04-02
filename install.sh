#!/bin/sh
set -e

echo
echo "Clopinet installer - v1" 
echo "======================="
echo
echo "This installer will download and compile everything that's needed to compile"
echo "and run ClopiNet network monitoring tools. Everything will be installed where"
echo "you run this from. No special priviledges are needed, except at the end for"
echo "the final touch (you will be prompted)."
echo
echo "The only requirements are:"
echo
echo "- wget or curl and a network connection to fetch packages"
echo "- the complete GNU C Compiler (gcc + gas + binutils) (reasonably up to date)"
echo "- the GNU make utility"
echo "- the development files for your libc (usually packaged under libc-dev on"
echo "  Debian like systems)"
echo "- perl 5 (to compile openssl) and various other UNIX tools (diff, time, sed...)"
echo "- the setcap utility to gain capability to sniff some traffic"
echo
echo "You will also need plenty of patience since compiling all this will take time."
echo
echo "press a key to start (CTRL-C to abort)"
read dummy

# Some variables one may want to change

OPAM_URL=http://www.ocamlpro.com/pub/opam-full-1.0.0.tar.gz
OCAML_URL=http://caml.inria.fr/pub/distrib/ocaml-4.00/ocaml-4.00.1.tar.gz
CLOPIREPO_URL=http://raw.github.com/rixed/clopam

TOPDIR="$PWD"
ROOTFS="$TOPDIR"
TMP="$TOPDIR"/tmp
BINDIR="$ROOTFS/bin"

export OPAMROOT="$ROOTFS/opam"
export PATH="$BINDIR:$PATH"
# Some programs may make use of that
export TMPDIR="$TMP"
export OPAMYES=1
export CFLAGS="-O2"
unset CPPFLAGS; export CPPFLAGS
unset LDFLAGS; export LDFLAGS

# Misc functions

die() {
	echo 1>&2 "$1"
	exit 1
}

action() {
	echo
	echo
	echo "$1"
	echo
}

notice() {
	echo "$1"
}

if which wget >/dev/null 2>/dev/null ; then
	WGET="wget --no-check-certificate --no-verbose"
elif which curl >/dev/null 2>/dev/null ; then
	WGET="curl --insecure --remote-name"
else
	die "Cannot find wget nor curl"
fi

download() {
	url="$1"
	f=$(basename "$url")
	action "Downloading $url"
	if test -r tmp/"$f" ; then
		notice "Reusing tmp/$f"
	else
		(cd "$TMP"; $WGET "$url")
	fi
}

#
# INSTALLATION
#

mkdir -p "$TMP" "$ROOTFS"

# OCAML
# Must start with this since we need it for OPAM

if test -x "$BINDIR/ocaml" ; then
	action "Reusing installed OCaml compiler"
else
	download "$OCAML_URL"

	action "Installing OCAML"
	tar zxf "$TMP"/$(basename "$OCAML_URL") -C "$TMP"
	(
		cd "$TMP"/$(basename "$OCAML_URL" .tar.gz)
		sed -i -e 's/^#include <misc.h>/#include "misc.h"/' otherlibs/unix/socketaddr.h
		./configure -no-tk -prefix "$ROOTFS"
		make world.opt
		make install
	) > "$TMP/ocaml.build.log"
	rm -rf "$TMP"/*
fi

# OPAM

if test -x "$BINDIR/opam" ; then
	action "Reusing installed OPAM package manager"
else
	download "$OPAM_URL"

	action "Installing OPAM"
	tar zxf "$TMP"/$(basename "$OPAM_URL") -C "$TMP"
	(
		cd "$TMP/"$(basename "$OPAM_URL" .tar.gz)
		./configure --prefix="$ROOTFS"
		make
		make install
	) > "$TMP/opam.build.log"
	rm -rf "$TMP"/*
fi

# Initialize OPAM

if test -d "$OPAMROOT" ; then
	action "OPAM is already initialized"
else
	action "Initializing OPAM"
	opam init --no-setup --jobs=3
fi

eval `opam config env`

# Adding local package repository

if "$BINDIR/opam" repository list | grep "$CLOPIREPO_URL" >/dev/null; then
	action "OPAM already configured - resynchronizing nonetheless"
	"$BINDIR/opam" update
else
	action "Configuring OPAM"
	"$BINDIR/opam" repository add clopinet "$CLOPIREPO_URL"
fi

# Install everything using OPAM

action "Using OPAM to install everything else"

"$BINDIR/opam" install all

# Final touch: give sniffing permissions

echo "Well, aparently everything went fine."
echo "Now you should give junkie (the sniffer) the capability to sniff network"
echo "packets, with this command (in root):"
echo
echo "  setcap cap_net_raw,cap_net_admin=eip $OPAMROOT/system/bin/junkie"
echo
echo
echo "Then you are read to run the whole system with:"
echo
echo "  $TOPDIR/clopinet"
echo
