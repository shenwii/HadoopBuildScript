#!/bin/sh

set -e

. "$(dirname "$0")/env"

check_root

_format_namenode() {
    runuser -u ${HADOOP_USER} -- ${HADOOP_HOME}/bin/hdfs namenode -format
}

_sync_namenode() {
    runuser -u ${HADOOP_USER} -- ${HADOOP_HOME}/bin/hdfs namenode -bootstrapStandby
}

_format_zk() {
    runuser -u ${HADOOP_USER} -- ${HADOOP_HOME}/bin/hdfs zkfc -formatZK
}

_systemd_script() {
    cat >/lib/systemd/system/hdfs@.service <<EOF
[Unit]
Description=The Hadoop HDFS Server
After=network.target

[Service]
Type=forking
User=${HADOOP_USER}
ExecStart=${HADOOP_HOME}/bin/hdfs --daemon start %i
ExecStop=${HADOOP_HOME}/bin/hdfs --daemon stop %i
KillMode=none
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    cat >/lib/systemd/system/yarn@.service <<EOF
[Unit]
Description=The Hadoop YARN Server
After=network.target

[Service]
Type=forking
User=${HADOOP_USER}
ExecStart=${HADOOP_HOME}/bin/yarn --daemon start %i
ExecStop=${HADOOP_HOME}/bin/yarn --daemon stop %i
KillMode=none
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    cat >/lib/systemd/system/mapred@.service <<EOF
[Unit]
Description=The Hadoop MAPRED Server
After=network.target

[Service]
Type=forking
User=${HADOOP_USER}
ExecStart=${HADOOP_HOME}/bin/mapred --daemon start %i
ExecStop=${HADOOP_HOME}/bin/mapred --daemon stop %i
KillMode=none
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

}

_reconfig() {
    runuser -u ${HADOOP_USER} -- touch "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export JAVA_HOME=$JAVA_HOME" >"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HADOOP_HOME=$HADOOP_HOME" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HDFS_NAMENODE_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HDFS_DATANODE_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HDFS_SECONDARYNAMENODE_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HDFS_ZKFC_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export HDFS_JOURNALNODE_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export YARN_RESOURCEMANAGER_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    echo "export YARN_NODEMANAGER_USER=${HADOOP_USER}" >>"$HADOOP_HOME/etc/hadoop/hadoop-env.sh"

    local i=1
    local quorum=""
    for node in $ZOOKEEPER_NODES; do
        if [ $i = 1 ]; then
            echo "$node" >"$HADOOP_HOME/etc/hadoop/workers"
            local quorum="$node:${ZOOKEEPER_CLIENT_PORT}"
        else
            echo "$node" >>"$HADOOP_HOME/etc/hadoop/workers"
            local quorum="${quorum},$node:${ZOOKEEPER_CLIENT_PORT}"
        fi
        local i=$((i+1))
    done

    runuser -u ${HADOOP_USER} -- touch "$HADOOP_HOME/etc/hadoop/core-site.xml"
    cat >"$HADOOP_HOME/etc/hadoop/core-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>${HADOOP_HDFS_CLUSTER}</value>
    </property>

    <property>
        <name>hadoop.tmp.dir</name>
        <value>${HADOOP_TMP_DIR}</value>
    </property>

    <property>
        <name>hadoop.http.staticuser.user</name>
        <value>${HADOOP_USER}</value>
    </property>

    <property>
        <name>ha.zookeeper.quorum</name>
        <value>${quorum}</value>
    </property>

    <property>
        <name>hadoop.zk.address</name>
        <value>${quorum}</value>
    </property>

    <property>
        <name>hadoop.proxyuser.${HIVE_USER}.hosts</name>
        <value>*</value>
    </property>

    <property>
        <name>hadoop.proxyuser.${HIVE_USER}.groups</name>
        <value>*</value>
    </property>
</configuration>
EOF

    local i=1
    local nns=""
    for node in $HADOOP_CLUSTER_NAMENODES; do
        if [ $i = 1 ]; then
            local nns="nn${i}"
        else
            local nns="${nns},nn${i}"
        fi
        local i=$((i+1))
    done

    local i=1
    local jns=""
    for node in $HADOOP_CLUSTER_JOURNALNODES; do
        if [ $i = 1 ]; then
            local jns="${node}:8485"
        else
            local jns="${jns};${node}:8485"
        fi
        local i=$((i+1))
    done

    runuser -u ${HADOOP_USER} -- touch "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
    cat <<EOF >"$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>dfs.nameservices</name>
        <value>${HADOOP_HDFS_NAMESERVICES}</value>
    </property>

    <property>
        <name>dfs.ha.namenodes.${HADOOP_HDFS_NAMESERVICES}</name>
        <value>${nns}</value>
    </property>

EOF

    local i=1
    for node in $HADOOP_CLUSTER_NAMENODES; do
        cat >>"$HADOOP_HOME/etc/hadoop/hdfs-site.xml" <<EOF
    <property>
        <name>dfs.namenode.rpc-address.${HADOOP_HDFS_NAMESERVICES}.nn${i}</name>
        <value>${node}:8020</value>
    </property>

EOF
        local i=$((i+1))
    done

    local i=1
    for node in $HADOOP_CLUSTER_NAMENODES; do
        cat >>"$HADOOP_HOME/etc/hadoop/hdfs-site.xml" <<EOF
    <property>
        <name>dfs.namenode.http-address.${HADOOP_HDFS_NAMESERVICES}.nn${i}</name>
        <value>${node}:9870</value>
    </property>

EOF
        local i=$((i+1))
    done
    cat >>"$HADOOP_HOME/etc/hadoop/hdfs-site.xml" <<EOF
    <property>
        <name>dfs.namenode.shared.edits.dir</name>
        <value>qjournal://${jns}/${HADOOP_HDFS_NAMESERVICES}</value>
    </property>

    <property>
        <name>dfs.journalnode.edits.dir</name>
        <value>${HADOOP_JOURNAL_DIR}</value>
    </property>

    <property>
        <name>dfs.ha.fencing.methods</name>
        <value>
            sshfence
            shell(/bin/true)
        </value>
    </property>

    <property>
        <name>dfs.ha.fencing.ssh.private-key-files</name>
        <value>${HADOOP_USER_HOME}/.ssh/id_rsa</value>
    </property>

    <property>
        <name>dfs.ha.automatic-failover.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>dfs.client.failover.proxy.provider.hdfs-cluster</name>
        <value>org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider</value>
    </property>
</configuration>
EOF

    runuser -u ${HADOOP_USER} -- touch "$HADOOP_HOME/etc/hadoop/mapred-site.xml"
    cat <<EOF >"$HADOOP_HOME/etc/hadoop/mapred-site.xml"
<?xml version="1.0"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>

    <property>
        <name>yarn.app.mapreduce.am.env</name>
        <value>HADOOP_MAPRED_HOME=\${HADOOP_HOME}</value>
    </property>

    <property>
        <name>mapreduce.map.env</name>
        <value>HADOOP_MAPRED_HOME=\${HADOOP_HOME}</value>
    </property>

    <property>
        <name>mapreduce.reduce.env</name>
        <value>HADOOP_MAPRED_HOME=\${HADOOP_HOME}</value>
    </property>

    <property>
        <name>mapreduce.jobhistory.address</name>
        <value>${HADOOP_JOBHISTORY_NODE}:10020</value>
    </property>

    <property>
        <name>mapreduce.jobhistory.webapp.address</name>
        <value>${HADOOP_JOBHISTORY_NODE}:19888</value>
    </property>

</configuration>
EOF

    local i=1
    local rms=""
    for node in $HADOOP_CLUSTER_RESOURCEMANAGERS; do
        if [ $i = 1 ]; then
            local rms="rm${i}"
        else
            local rms="${rms},rm${i}"
        fi
        local i=$((i+1))
    done

    runuser -u ${HADOOP_USER} -- touch "$HADOOP_HOME/etc/hadoop/yarn-site.xml"
    cat <<EOF >"$HADOOP_HOME/etc/hadoop/yarn-site.xml"
<?xml version="1.0"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>

    <property>
        <name>yarn.resourcemanager.ha.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.resourcemanager.cluster-id</name>
        <value>${HADOOP_YARN_CLUSTER_ID}</value>
    </property>

    <property>
        <name>yarn.resourcemanager.ha.rm-ids</name>
        <value>${rms}</value>
    </property>
EOF

    local i=1
    for node in $HADOOP_CLUSTER_RESOURCEMANAGERS; do
        cat <<EOF >>"$HADOOP_HOME/etc/hadoop/yarn-site.xml"
    <property>
        <name>yarn.resourcemanager.hostname.rm${i}</name>
        <value>${node}</value>
    </property>

EOF
        local i=$((i+1))
    done

    local i=1
    for node in $HADOOP_CLUSTER_RESOURCEMANAGERS; do
        cat <<EOF >>"$HADOOP_HOME/etc/hadoop/yarn-site.xml"
    <property>
        <name>yarn.resourcemanager.webapp.address.rm${i}</name>
        <value>${node}:8088</value>
    </property>

EOF
        local i=$((i+1))
    done

    cat <<EOF >>"$HADOOP_HOME/etc/hadoop/yarn-site.xml"
    <property>
        <name>yarn.resourcemanager.recovery.enabled</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.resourcemanager.store.class</name>
        <value>org.apache.hadoop.yarn.server.resourcemanager.recovery.ZKRMStateStore</value>
    </property>

    <property>
        <name>yarn.log-aggregation-enable</name>
        <value>true</value>
    </property>

    <property>
        <name>yarn.log.server.url</name>
        <value>http://${HADOOP_JOBHISTORY_NODE}:19888/jobhistory/logs</value>
    </property>

    <property>
        <name>yarn.log-aggregation.retain-seconds</name>
        <value>604800</value>
    </property>

    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>128</value>
    </property>

    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>${HADOOP_MAX_MEM}</value>
    </property>

    <property>
        <name>yarn.scheduler.vmem-pmem-ratio</name>
        <value>4</value>
    </property>

</configuration>
EOF
    _systemd_script
    systemctl daemon-reload
}

_install() {
    create_user "$HADOOP_USER" "$HADOOP_USER_HOME"
    dirname="$(download_apache_software "/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" "$HADOOP_USER" "$HADOOP_USER_HOME")"
    cd "$HADOOP_USER_HOME"
    runuser -u "$HADOOP_USER" -- ln -fs "$dirname" "$(basename "$HADOOP_HOME")"
    _reconfig
}

case "$1" in
    "install")
        _install
    ;;
    "reconfig")
        _reconfig
    ;;
    "format-namenode")
        _format_namenode
    ;;
    "format-zk")
        _format_zk
    ;;
    "sync-namenode")
        _sync_namenode
    ;;
    * )
        echo "$(basename "$0") install|reconfig|format-namenode|format-zk|sync-namenode"
        exit 1
    ;;
esac
