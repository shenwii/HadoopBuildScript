#!/bin/sh

set -e

. "$(dirname "$0")/env"

check_root

_systemd_script() {
    cat >/lib/systemd/system/zookeeper.service <<EOF
[Unit]
Description=The Zookeeper Server
After=network.target

[Service]
Type=forking
User=${ZOOKEEPER_USER}
ExecStart=${ZOOKEEPER_USER_HOME}/bin/zkServer.sh start
ExecStop=${ZOOKEEPER_USER_HOME}/bin/zkServer.sh stop
KillMode=none
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

_reconfig() {
    runuser -u $ZOOKEEPER_USER -- touch "${ZOOKEEPER_USER_HOME}/conf/zoo.cfg"
    runuser -u $ZOOKEEPER_USER -- mkdir -p "${ZOOKEEPER_DATA_DIR}"
    runuser -u $ZOOKEEPER_USER -- touch "${ZOOKEEPER_DATA_DIR}/myid"

    cat >"${ZOOKEEPER_USER_HOME}/conf/zoo.cfg" <<EOF
tickTime=2000
initLimit=10
syncLimit=5
dataDir=${ZOOKEEPER_DATA_DIR}
clientPort=${ZOOKEEPER_CLIENT_PORT}
EOF
    local _id=0
    for node in $ZOOKEEPER_NODES; do
        local _host="$node"
        local _my_host="$(hostname)"
        echo "server.${_id}=${_host}:2888:3888" >>"${ZOOKEEPER_USER_HOME}/conf/zoo.cfg"
        if [ "$_my_host" = "$_host" ]; then
            echo "$_id" >"${ZOOKEEPER_DATA_DIR}/myid"
        fi
        local _id=$((${_id}+1))
    done
    _systemd_script
    systemctl daemon-reload
}

_install() {
    create_user "$ZOOKEEPER_USER" "$ZOOKEEPER_USER_HOME"
    dirname="$(download_apache_software "/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz" "$ZOOKEEPER_USER" "$ZOOKEEPER_USER_HOME")"
    runuser -u $ZOOKEEPER_USER -- cp -rp "$ZOOKEEPER_USER_HOME/$dirname"/* "$ZOOKEEPER_USER_HOME"/
    rm -rf "$ZOOKEEPER_USER_HOME/$dirname"
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
