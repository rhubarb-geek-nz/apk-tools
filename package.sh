#!/bin/sh -e
# Tool to package the Alpine apk-tools as formal package
# Copyright (C) 2023 Roger Brown

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

PACKAGE=apk-tools
VERSION=2.14.0
RELEASE=1

if test -z "$MAINTAINER"
then
	if git config user.email > /dev/null
	then
		MAINTAINER="$(git config user.email)"
	else
		echo MAINTAINER not set 1>&2
		false
	fi
fi

mkdir work

cleanup()
{
	chmod -R +w work
	rm -rf work apk-tools rpm.spec rpms
}

trap cleanup 0

git -c advice.detachedHead=false clone --single-branch --branch "v$VERSION" https://github.com/alpinelinux/apk-tools.git apk-tools

(
	set -e

	cd apk-tools

	make LUA=no

	if make install LUA=no DESTDIR=$(pwd)/../work
	then
		:
	else
		LD_LIBRARY_PATH=../work/lib ../work/sbin/apk --version

		rm -rf ../work/usr/share

		mkdir -p ../work/usr/share/doc/apk

		mv README.md ../work/usr/share/doc/apk/

		curl --silent --fail --location --output "apk-tools-doc-$VERSION-r2.apk" "https://dl-cdn.alpinelinux.org/alpine/v3.18/main/x86_64/apk-tools-doc-$VERSION-r2.apk"

		tar --extract --gzip --file  "apk-tools-doc-$VERSION-r2.apk" --warning=no-unknown-keyword -C ../work usr/share/man
	fi
)

(
	set -e

	cd work

	mkdir -p control data/usr/bin data/usr/lib

	find usr/share lib -type f | xargs chmod gou-x 

	mv "lib/libapk.so.$VERSION" data/usr/lib

	strip sbin/apk

	mv sbin/apk data/usr/bin

	mv usr/share data/usr

	find data/usr/share/man -type f | while read N
	do
		case "$N" in
			*.gz )
				;;
			* )
				gzip "$N"
				;;
		esac
	done

	chmod -R -w data

	if dpkg --print-architecture
	then
		DPKGARCH=$(dpkg --print-architecture)

		SIZE=$( du -sk data | while read A B; do echo $A; done)

		cat > control/control <<EOF
Package: $PACKAGE
Version: $VERSION-$RELEASE
Architecture: $DPKGARCH
Installed-Size: $SIZE
Maintainer: $MAINTAINER
Section: utils
Priority: extra
Description: Alpine Package Keeper - package manager for alpine
EOF

		for d in data control
		do
			(
				set -e

				cd "$d"

				tar --owner=0 --group=0 --create --xz --file "../$d.tar.xz" $(find * -type f | grep -v README) $(find * -name apk -type d)
			)
		done

		echo "2.0" >debian-binary

		ar r "$PACKAGE"_"$VERSION-$RELEASE"_"$DPKGARCH".deb debian-binary control.tar.* data.tar.*

		mv *.deb ..
	fi
)

if rpmbuild --version
then
	cat > rpm.spec <<EOF
Summary: Alpine Package Keeper - package manager for alpine
Name: $PACKAGE
Version: $VERSION
Release: $RELEASE
Group: Development/Tools
License: GPL-2.0-only
Packager: $MAINTAINER
Autoreq: 0
AutoReqProv: no
Prefix: /

%description
Alpine Package Keeper - package manager for alpine

%files
%defattr(-,root,root)
/usr/lib/libapk.so.2.14.0
/usr/bin/apk
/usr/share/man/man*/*.gz
/usr/share/doc/apk

%clean

EOF

	PWD=`pwd`

	rpmbuild --buildroot "$PWD/work/data" --define "_rpmdir $PWD/rpms" -bb "$PWD/rpm.spec" --define "_build_id_links none" 

	find rpms -type f -name "*.rpm" | while read N
	do
		mv "$N" .
		basename "$N"
	done
fi
