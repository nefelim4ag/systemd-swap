Name: systemd-swap
Summary: Script for creating hybrid swap space from zram swaps, swap files and swap partitions.

Version: %(git tag | tail -n 1)
Release: 1%{?dist}

URL: https://github.com/Nefelim4ag/systemd-swap/
License: GPLv3

Source0: %{name}
BuildArch: noarch

Source1: swap.conf
Source2: systemd-swap.service

Requires: util-linux

%description
%{summary}

%install
rm -rf %{buildroot}/
mkdir -p  %{buildroot}/

make install PREFIX=%{buildroot}/ # % {_bindir}/

%clean
rm -rf %{buildroot}/

%files
%defattr(-,root,root,-)
%{_bindir}/*
%{_datadir}/%{name}/*
/usr/lib/systemd/system/*
/var/lib/*

%changelog
* Sun Jun 10 2018  nefelim4ag <nefelim4ag@gmail.com> %{version}
- Version: %{version}

