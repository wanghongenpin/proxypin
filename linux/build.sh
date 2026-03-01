#!/bin/bash

pwd
cd ../build/linux/x64/release
rm -rf package
mkdir -p package/DEBIAN
echo "Package: ProxyPin" >> package/DEBIAN/control
echo "Version: 1.2.6" >> package/DEBIAN/control
echo "Priority: optional" >> package/DEBIAN/control
echo "Architecture: amd64" >> package/DEBIAN/control
echo "Depends: ca-certificates" >> package/DEBIAN/control
echo "Section: utils" >> package/DEBIAN/control
echo "Maintainer: wanghongenpin@gmail.com" >> package/DEBIAN/control
echo "Homepage: https://github.com/wanghongenpin/proxypin" >> package/DEBIAN/control
echo "Description: http/https Capture packets" >> package/DEBIAN/control
echo "" >> package/DEBIAN/control
mkdir -p package/usr/share/applications
cp ../../../../linux/proxy-pin.desktop package/usr/share/applications
mkdir package/opt
cp -r bundle package/opt/proxypin

dpkg -b package ProxyPin-Linux.deb
