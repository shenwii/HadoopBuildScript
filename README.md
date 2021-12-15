# Hadoop平台搭建脚本

## 介绍

这个一套分布式高可用的Hadoop平台搭建脚本，包括：

* Zookeeper
* Hadoop
* Hive
* Hbase

## 需求

* Linux（脚本在debian上测试过，其他平台理论上通用）
* wget
* systemd
* alternatives（安装JDK8需要）

## 教程

### 1.设置网络

网络推荐通过DHCP服务器（通常为路由器）统一管理与设置

如果需要手动设置的，不同Linux发行版请自行google

### 2.设置主机名

将各个节点的主机名，通过下面命令修改成你想要的主机名

```shell
#xxx为主机名
hostnamectl set-hostname xxx
```

不同Linux发行版修改主机名方法可能不同，如果不同的请自行google

### 3.修改hosts

如果通过DHCP服务器统一管理网络的，则只需要将自己节点的记录删除就行，比如

删除这一行：

> 127.0.1.1 node1

如果是静态IP的，则还需要自己在hosts中绑定每个节点，比如

> 192.168.1.100 node1
>
> 192.168.1.101 node2
>
> 192.168.1.102 node3

### 4.修改环境变量

修改`env`文件，将里面的node1，node2，node3修改成你实际node节点的主机名，同时可以适当的增减node节点

### 5.设置时区以及同步时间

不同发行版请自行google

### 6.安装JDK8

如果发行版自带JDK8的，可以直接使用发行版的JDK，比如

```shell
#rpm系
yum install java-1.8.0-openjdk
#deb系
apt install openjdk-8-jdk
#不同发行版之间包名可能略有不同，可以自行google
```

如果发行版不带JDK，则可以通过`install_jdk8.sh`安装

```shell
#这个脚本需要Linux发行版带alternatives
#如果没有alternatives的，请自行配置环境变量
./install_jdk8.sh
```

### 7.安装Zookeeper集群

```shell
#以下命令需要在每个zookeeper节点上执行
#安装过程中需要输入新建的zookeeper用户的密码
./zookeeper.sh install
#启动zookeeper集群
systemctl start zookeeper
#查看服务状态
systemctl status zookeeper
#设为开机自启
systemctl enable zookeeper
```

### 8.安装hadoop集群

```shell
#以下命令需要在每个hadoop节点上执行
#安装过程中需要输入新建的hadoop用户的密码
./hadoop.sh install
```

安装了hadoop之后，会创建hadoop用户，此时可以先配置各个节点之间的免密登入

```shell
#以node1为例
#先以hadoop用户登入node1节点
#首先创建密钥
ssh-keygen
#将密钥复制到其他节点去
ssh-copy-id -i $HOME/.ssh/id_rsa.pub node2
ssh-copy-id -i $HOME/.ssh/id_rsa.pub node3

#然后分别登入node2和node3，重复上面操作
```

首先需要在journal节点上启动journalnode，默认配置中是node2和node3节点

`HADOOP_CLUSTER_JOURNALNODES="node2 node3"`

```shell
#在node2和node3节点上启动journalnode
systemctl start hdfs@journalnode
#查看服务状态
systemctl status hdfs@journalnode
#设为开机自启
systemctl enable hdfs@journalnode
```

然后配置name node，默认配置中node1和node2节点

`HADOOP_CLUSTER_NAMENODES="node1 node2"`

```shell
#首先在任一name node节点上格式化，这里选node1为例
#登入node1
./hadoop.sh format-namenode
#然后启动namenode
systemctl start hdfs@namenode
#查看服务状态
systemctl status hdfs@namenode
#设为开机自启
systemctl enable hdfs@namenode

#然后在其他节点上，同步namenode并且启动
#这里总共就配置了2个namenode，所以剩下的其他节点只有node2，实际以实际情况为准
#登入node2
./hadoop.sh sync-namenode
#然后启动namenode
systemctl start hdfs@namenode
#查看服务状态
systemctl status hdfs@namenode
#设为开机自启
systemctl enable hdfs@namenode

#然后在任意namenode节点上格式化zkfc
./hadoop.sh format-zk
#在全部namenode节点上启动zkfc（这里是node1和node2）
systemctl start hdfs@zkfc
#查看服务状态
systemctl status hdfs@zkfc
#设为开机自启
systemctl enable hdfs@zkfc
```

配置resource manager，默认配置中是node1和node3节点

`HADOOP_CLUSTER_RESOURCEMANAGERS="node1 node3"`

```shell
#在node1和node3节点上启动resource manager
systemctl start yarn@resourcemanager
#查看服务状态
systemctl status yarn@resourcemanager
#设为开机自启
systemctl enable yarn@resourcemanager
```

配置job history，默认配置中是node2节点

`HADOOP_JOBHISTORY_NODE="node2"`

```shell
#在node2节点上启动job history
systemctl start mapred@historyserver
#查看服务状态
systemctl status mapred@historyserver
#设为开机自启
systemctl enable mapred@historyserver
```

在所有hadoop节点上启动data node和node manager

```shell
#在所有hadoop节点上启动data node和node manager
systemctl start hdfs@datanode
systemctl start yarn@nodemanager
#查看服务状态
systemctl status hdfs@datanode
systemctl status yarn@nodemanager
#设为开机自启
systemctl enable hdfs@datanode
systemctl enable yarn@nodemanager
```

### 9.安装Hive

hive需要使用mysql或者其他数据库储存元数据，这里以mysql为例

如何安装mysql，以及配置mysql用户名密码等，请自行google，如果已有mysql的可以跳过

首先确认下`env`文件中的mysql连接方式是否正确

>#MySQL的JDBC驱动版本
>
>HIVE_MYSQL_DRIVER_VERSION="8.0.27"
>
>#MySQL的JDBC驱动
>
>HIVE_MYSQL_DRIVER="com.mysql.cj.jdbc.Driver"
>
>#MySQL的连接URL
>
>HIVE_MYSQL_URL="jdbc:mysql://node1:3306/hive?autoReconnect=true&amp;serverTimezone=Asia/Shanghai&amp;useSSL=false&amp;allowMultiQueries=true"
>
>#MySQL的用户名
>
>HIVE_MYSQL_USER="hive"
>
>#MySQL的密码
>
>HIVE_MYSQL_PASSWD="hive123"

确认无误后，配置hive

```shell
#只需要在任意服务器上安装
./hive.sh install
#初始化元数据
#如果mysql连接配置有误，这里会报错
./hive.sh init-db
#启动hive元数据储存
systemctl start hive@metastore
#查看服务状态
systemctl status hive@metastore
#设为开机自启
systemctl enable hive@metastore
#启动hive server2
systemctl start hive@hiveserver2
#查看服务状态
systemctl status hive@hiveserver2
#设为开机自启
systemctl enable hive@hiveserver2
```

### 10.安装HBase

在任意HBase节点安装

```shell
#在任意HBase节点安装
./hbase.sh install
#启动hbase
systemctl start hbase
#查看服务状态
systemctl status hbase
#配置开机自启
#如果在各个hbase节点之间配置了免密登入，节点之间应该可以互相启动，所以开机自启请自行测试
systemctl enable hbase
```

## 修改配置

如果需要修改配置的话，直接在各个shell脚本里修改配置，修改完成后可以通过reconfig来刷新配置

比如以修改hadoop配置为例

```shell
#重新生成配置文件
./hadoop.sh reconfig
#按需重启服务
#这里只是例子
systemctl restart hdfs@datanode
#......类似的重启其他服务
```

