#!/bin/sh
set -e

echo
echo "Clopinet installer - v1" 
echo "======================="
echo
echo "This installer will download and compile everything that's needed to compile"
echo "and run ClopiNet network monitoring tools. Everything will be installed where"
echo "you run this from. No special privileges are needed, except at the end for"
echo "the final touch (you will be prompted)."
echo
echo "The only requirements are:"
echo
echo "- wget or curl and a network connection to fetch packages"
echo "- the complete GNU C Compiler (gcc + gas + binutils) (reasonably up to date)"
echo "- the GNU make utility"
echo "- the rsync utility"
echo "- bison and flex (or other sufficiently good yacc and lex)"
echo "- the development files for your libc (usually packaged under libc-dev on"
echo "  Debian like systems)"
echo "- perl 5 (to compile openssl) and various other UNIX tools (such as diff,"
echo "  time, sed, gunzip...)"
echo "- optionally, if you want netgraph chart: graphviz"
echo
echo "You will also need plenty of patience since compiling all this will take time."
echo "Also, this is recommended to save this script output into a file in order to"
echo "help troubleshooting should something goes wrong (using the tee command for"
echo "instance)."
echo
echo "press a key to start (CTRL-C to abort)"
read dummy

# Some variables one may want to change

OPAM_URL=http://www.ocamlpro.com/pub/opam-full-1.0.0.tar.gz
OCAML_URL=http://caml.inria.fr/pub/distrib/ocaml-4.00/ocaml-4.00.1.tar.gz
CLOPIREPO_URL=git://github.com/rixed/clopam.git
GEOIPDB_URL=http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz

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
	WGET="wget --no-check-certificate --no-verbose --continue"
elif which curl >/dev/null 2>/dev/null ; then
	WGET="curl --insecure --remote-name --silent --continue-at -"
else
	die "Cannot find wget nor curl"
fi

download() {
	url="$1"
	f=$(basename "$url")
	action "Downloading $url"
	(cd "$TMP"; $WGET "$url")
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
	)
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
		mkdir "$ROOTFS"/lib/ocaml/labltk # or make will fail
		make
		make install
	)
	rm -rf "$TMP"/*
fi

# Initialize OPAM

if test -d "$OPAMROOT" ; then
	action "OPAM is already initialized"
	# OPAM fail to upgrade a repo if the tracked head was `push -f`ed
	if test -d "$OPAMROOT/repo/clopinet/.git"; then
		(cd "$OPAMROOT/repo/clopinet"
		git fetch --all
		git reset --hard origin/master)
	fi
else
	action "Initializing OPAM"
	# Wait for opam 1.0.1 to set more jobs
	opam init --no-setup --jobs=1
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

clean_out() {
	sleep 1
	echo
	echo
	echo
}

if "$BINDIR/opam" install all ; then
	clean_out

	# Little bit of cleaning
	rm -rf "$OPAMROOT"/repo/clopinet/tmp/* "$OPAMROOT"/archives/* || true

	# Install better GeoIP database
	if ! test -e "$OPAMROOT"/system/share/GeoIP/GeoIPCity.dat ; then
		echo "This product includes GeoLite data created by MaxMind, available from"
		echo " <a href="http://www.maxmind.com">http://www.maxmind.com</a>."
		echo "Installing the free City GeoIP Database"
		download "$GEOIPDB_URL"
		mkdir -p "$OPAMROOT"/system/share/GeoIP
		# Notice we must rename the file or stupid GeoIP won't look for it
		GEOIPDB="$OPAMROOT"/system/share/GeoIP/GeoIPCity.dat
		(
			gunzip -c "$TMP"/GeoLiteCity.dat.gz > "$GEOIPDB" &&
			rm -rf "$TMP"/* &&
			echo "done"
		) || rm -f "$GEOIPDB"
		echo "done"
		echo
	fi

	# Final touch: give sniffing permissions
	echo "Well, apparently everything went fine."
	echo "Now you should give junkie (the sniffer) the capability to sniff network"
	echo "packets, with this command (in root):"
	echo
	echo "  setcap cap_net_raw,cap_net_admin=eip $OPAMROOT/system/bin/junkie"
	echo
	echo "Note that, on Debian systems, setcap comes with the libcap2-bin package."
	echo
	echo
	echo "Have a look at '$OPAMROOT/system/etc/clopinet.conf' for some customization,"

	# Top level script
	env="$TOPDIR/env"
	echo "eval \$(OPAMROOT='$OPAMROOT' '$BINDIR/opam' config env)" > "$env"
	echo "LD_LIBRARY_PATH='$OPAMROOT/system/lib'; export LD_LIBRARY_PATH" >> "$env"
	echo ". '$OPAMROOT/system/etc/clopinet.conf'" >> "$env"

	echo "then source the toplevel environment file with:"
	echo
	echo "  . $TOPDIR/env"
	echo
	echo "you can then start the system with:"
	echo
	echo "  $OPAMROOT/system/bin/clopinet start"
	echo
else
	clean_out
	echo "Installation failed."
	echo "If you encountered downloading problems than you can retry later - this"
	echo "installation script will skip steps that succeeded."
fi

