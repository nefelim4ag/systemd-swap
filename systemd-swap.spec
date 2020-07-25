%global snapver %(git describe --tags --abbrev=0)
%global commit %(git rev-parse --verify --short=7 HEAD)

Name: systemd-swap
Summary: Creating hybrid swap space from zram swaps, swap files and swap partitions

Version: %{snapver}
Release: 0.git%{commit}%{?dist}

URL: https://github.com/Nefelim4ag/systemd-swap/
License: GPLv3+

Source: %{name}
BuildArch: noarch

%if 0%{?fedora} >= 31
BuildRequires: systemd-rpm-macros
%else
BuildRequires: systemd-units
%endif
%{?systemd_requires}

Requires: util-linux
Requires: kmod
Requires: kmod(zram.ko)
Requires: python(abi) >= 3.7
Requires: python3-systemd
Requires: python3-sysv_ipc

%description
Systemd-swap manages the configuration of zram and zswap and allows for automatically setting up swap files through swapfc and automatically enables availible swapfiles and swap partitions.

%prep

%build

%install
%make_install

%post
%systemd_post systemd-swap.service

%preun
%systemd_preun systemd-swap.service

%postun
%systemd_postun_with_restart systemd-swap.service

%files
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/systemd/swap.conf
%{_unitdir}/%{name}.service
%{_bindir}/%{name}
%{_mandir}/man5/swap.conf.5*
%{_mandir}/man8/%{name}.8*
%dir %{_datadir}/%{name}/
%{_datadir}/%{name}/swap-default.conf

%ghost %dir %{_sharedstatedir}/%{name}
%ghost %dir %{_sharedstatedir}/%{name}/swapfc
%ghost %{_sharedstatedir}/%{name}/*

%changelog
* Tue Jun 16 2020 zenofile <tschubert@bafh.org> %{version}-%{release}
- use DESTDIR instead of PREFIX
- more granular file and directory ownership
- handle service restart
- include manual pages and license
- Fedora compatible versioning

* Sun Jun 10 2018  nefelim4ag <nefelim4ag@gmail.com>
- initial version
