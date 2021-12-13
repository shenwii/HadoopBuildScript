#!/bin/sh

set -e

. "$(dirname "$0")/env"

check_root

_systemd_script() {
    cat >/lib/systemd/system/hbase.service <<EOF
[Unit]
Description=The Hadoop HBASE Server
After=network.target

[Service]
Type=forking
User=${HBASE_USER}
ExecStart=${HBASE_HOME}/bin/start-hbase.sh
ExecStop=${HBASE_HOME}/bin/stop-hbase.sh
KillMode=none
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

_reconfig() {
    runuser -u ${HBASE_USER} -- touch "$HBASE_HOME/conf/hbase-env.sh"
    runuser -u ${HBASE_USER} -- mkdir -p $HBASE_HOME/tmp

    cd $HBASE_HOME/conf
    ln -fs "$HADOOP_HOME/etc/hadoop/core-site.xml" ./
    ln -fs "$HADOOP_HOME/etc/hadoop/hdfs-site.xml" ./

    echo "export JAVA_HOME=${JAVA_HOME}" >"$HBASE_HOME/conf/hbase-env.sh"
    echo "export HBASE_MANAGES_ZK=false" >>"$HBASE_HOME/conf/hbase-env.sh"
    echo "export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=true" >>"$HBASE_HOME/conf/hbase-env.sh"

    local i=1
    local quorum=""
    for node in $ZOOKEEPER_NODES; do
        if [ $i = 1 ]; then
            echo "$node" >"$HBASE_HOME/conf/regionservers"
            local quorum="$node:${ZOOKEEPER_CLIENT_PORT}"
        else
            echo "$node" >>"$HBASE_HOME/conf/regionservers"
            local quorum="${quorum},$node:${ZOOKEEPER_CLIENT_PORT}"
        fi
        local i=$((i+1))
    done

    runuser -u ${HBASE_USER} -- touch "$HBASE_HOME/conf/hbase-site.xml"
    cat >"$HBASE_HOME/conf/hbase-site.xml" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>hbase.cluster.distributed</name>
    <value>true</value>
  </property>
  <property>
    <name>hbase.tmp.dir</name>
    <value>$HBASE_HOME/tmp</value>
  </property>
  <property>
    <name>hbase.unsafe.stream.capability.enforce</name>
    <value>false</value>
  </property>
  <property>
    <name>hbase.rootdir</name>
    <value>${HADOOP_HDFS_CLUSTER}/hbase</value>
  </property>
  <property>
    <name>hbase.zookeeper.quorum</name>
    <value>${quorum}</value>
  </property>
</configuration>

EOF
    _systemd_script
    systemctl daemon-reload
}

_install() {
    create_user "$HBASE_USER" "$HBASE_USER_HOME"
    dirname="$(download_apache_software "/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz" "$HBASE_USER" "$HBASE_USER_HOME")"
    cd "$HBASE_USER_HOME"
    runuser -u "$HBASE_USER" -- ln -fs "$dirname" "$(basename "$HBASE_HOME")"
    _reconfig
}

case "$1" in
    "install")
        _install
    ;;
    "reconfig")
        _reconfig
    ;;
    * )
        echo "$(basename "$0") install|reconfig"
        exit 1
    ;;
esac
