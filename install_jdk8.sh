#!/bin/sh

set -e

java_bin="java \
javac \
jps"
if [ -d "/usr/lib/jvm/java-8-openjdk-amd64" ]; then exit 0; fi

wget 'https://builds.openlogic.com/downloadJDK/openlogic-openjdk/8u262-b10/openlogic-openjdk-8u262-b10-linux-x64.tar.gz' -O "/tmp/openlogic-openjdk-8u262-b10-linux-x64.tar.gz"
if ! [ -d "/usr/lib/jvm" ]; then mkdir "/usr/lib/jvm"; fi
cd "/usr/lib/jvm"
tar -xvzf "/tmp/openlogic-openjdk-8u262-b10-linux-x64.tar.gz" && rm "/tmp/openlogic-openjdk-8u262-b10-linux-x64.tar.gz"
mv "openlogic-openjdk-8u262-b10-linux-64" "java-8-openjdk-amd64"
for f in $java_bin; do
    if [ -f /usr/lib/jvm/java-8-openjdk-amd64/bin/$f ]; then
        update-alternatives --install /usr/bin/$f $f /usr/lib/jvm/java-8-openjdk-amd64/bin/$f 100
        update-alternatives --config $f
    fi
done
