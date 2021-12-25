#!/bin/sh

set -e

. "$(dirname "$0")/env"

check_root

_systemd_script() {
    cat >/etc/systemd/system/hive@.service <<EOF
[Unit]
Description=The Hadoop HIVE Server
After=network.target

[Service]
Type=simple
User=${HIVE_USER}
ExecStart=${HIVE_HOME}/bin/hive --service %i
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

_reconfig() {
    runuser -u ${HIVE_USER} -- mkdir -p ${HIVE_USER_HOME}/tmp/${HIVE_USER}
    runuser -u ${HIVE_USER} -- mkdir -p ${HIVE_USER_HOME}/logs

    cat >"$HIVE_HOME/conf/hive-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export HIVE_HOME=$HIVE_HOME
export HIVE_CONF_DIR=$HIVE_HOME/conf
export HIVE_LOG_DIR=${HIVE_USER_HOME}/logs
export HIVE_AUX_JARS_PATH=$HIVE_HOME/lib
EOF

    #echo "property.hive.log.dir=$HIVE_HOME/logs" >"$HIVE_HOME/conf/hive-log4j2.properties"

    cat >"$HIVE_HOME/conf/hive-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>${HIVE_MYSQL_DRIVER}</value>
    <description>Driver class name for a JDBC metastore</description>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>${HIVE_MYSQL_URL}</value>
    <description>
      JDBC connect string for a JDBC metastore.
      To use SSL to encrypt/authenticate the connection, provide database-specific SSL flag in the connection URL.
      For example, jdbc:postgresql://myhost/db?ssl=true for postgres database.
    </description>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>${HIVE_MYSQL_USER}</value>
    <description>Username to use against metastore database</description>
  </property>

  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>${HIVE_MYSQL_PASSWD}</value>
    <description>password to use against metastore database</description>
  </property>

  <property>
    <name>hive.exec.local.scratchdir</name>
    <value>${HIVE_USER_HOME}/tmp/${HIVE_USER}</value>
    <description>Local scratch space for Hive jobs</description>
  </property>

  <property>
    <name>hive.downloaded.resources.dir</name>
    <value>${HIVE_USER_HOME}/tmp/\${hive.session.id}_resources</value>
    <description>Temporary local directory for added resources in the remote file system.</description>
  </property>

  <property>
    <name>hive.querylog.location</name>
    <value>${HIVE_USER_HOME}/tmp/${HIVE_USER}</value>
    <description>Location of Hive run time structured log file</description>
  </property>

  <property>
    <name>hive.server2.logging.operation.log.location</name>
    <value>${HIVE_USER_HOME}/tmp/${HIVE_USER}/operation_logs</value>
    <description>Top level directory where operation logs are stored if logging functionality is enabled</description>
  </property>

  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://0.0.0.0:9083</value>
    <description>Thrift URI for the remote metastore. Used by metastore client to connect to remote metastore.</description>
  </property>

  <property>
    <name>hive.server2.thrift.bind.host</name>
    <value>0.0.0.0</value>
    <description>Bind host on which to run the HiveServer2 Thrift service.</description>
  </property>
</configuration>
EOF
    wget "https://repo1.maven.org/maven2/mysql/mysql-connector-java/${HIVE_MYSQL_DRIVER_VERSION}/mysql-connector-java-${HIVE_MYSQL_DRIVER_VERSION}.jar" -O $HIVE_HOME/lib/mysql-connector-java-${HIVE_MYSQL_DRIVER_VERSION}.jar
    _systemd_script
    systemctl daemon-reload
}

_install() {
    create_user "$HIVE_USER" "0"
    if ! [ -d "$HIVE_USER_HOME" ]; then
        mkdir -p "$HIVE_USER_HOME"
        chown "$HIVE_USER:$HIVE_USER" "$HIVE_USER_HOME"
    fi
    if [ -d "$HIVE_HOME" ]; then rm -rf "$HIVE_HOME"; fi
    dirname="$(download_apache_software "/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" "$(dirname "$HIVE_HOME")")"
    mv "$(dirname "$HIVE_HOME")/${dirname}" "$HIVE_HOME"
    rm ${HIVE_HOME}/lib/guava-*.jar
    cp ${HADOOP_HOME}/share/hadoop/common/lib/guava-*.jar ${HIVE_HOME}/lib/
    _reconfig
}

_init_db() {
    runuser -u $HIVE_USER -- ${HIVE_HOME}/bin/schematool -dbType mysql -initSchema
}

case "$1" in
    "install")
        _install
    ;;
    "reconfig")
        _reconfig
    ;;
    "init-db")
        _init_db
    ;;
    * )
        echo "$(basename "$0") install|reconfig|init-db"
        exit 1
    ;;
esac
