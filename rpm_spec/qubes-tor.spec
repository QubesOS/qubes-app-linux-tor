#
# This is the SPEC file for creating binary and source RPMs for the VMs.
#
#
# The Qubes OS Project, http://www.qubes-os.org
#
# Copyright (C) 2012-2013 Abel Luck <abel@outcomedubious.im>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#

%{!?version: %define version %(cat version)}

Name:		qubes-tor
Version:	%{version}
Release:	1%{dist}
Summary:	The Qubes package for running a TorVM

Group:		Qubes
Vendor:		Invisible Things Lab
License:	GPL
URL:		http://www.qubes-os.org

Requires:	systemd
Requires:       qubes-tor-repo
Requires:       tor >= 0.2.3

Obsoletes:  qubes-tor-init

%description
A tor distribution for Qubes OS

%define _builddir %(pwd)

%package repo
Summary: Torproject RPM repository


%description repo
The torproject's Fedora repository and GPG key

%prep

%build

%install
rm -rf $RPM_BUILD_ROOT
make install-rh DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%dir /usr/lib/qubes-tor
%attr(0744,root,root) /usr/lib/qubes-tor/start_tor_proxy.sh
/usr/lib/qubes-tor/torrc.tpl
/usr/lib/qubes-tor/torrc
/usr/lib/qubes-tor/README
/etc/udev/rules.d/99-qubes-tor-hook.rules
%attr(0644,root,root) /lib/systemd/system/qubes-tor.service 

%files repo
%defattr(-,root,root,-)
/etc/yum.repos.d/torproject.repo
/etc/pki/rpm-gpg/RPM-GPG-KEY-torproject.org.asc

%post
/bin/systemctl enable qubes-tor.service 2> /dev/null
if [ $1 -eq 1 ]; then
    /sbin/chkconfig tor off 2> /dev/null
fi

%changelog
* Tue Mar 12 2013 Abel Luck <abel@outcomedubious.im> 0.1.1
- Support custom Tor settings
- Robustly handle error conditions
* Sat Mar 09 2013 Abel Luck <abel@outcomedubious.im> 0.1
- Persist tor's DataDirectory
- Documenation updates
- Lessen default stream isolation settings
* Fri Oct 12 2012 Abel Luck <abel@outcomedubious.im> 0.1beta1
- Initial release
