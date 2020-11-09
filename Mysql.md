[toc]

# 基本架构

![image](http://eternityz.gitee.io/image/image_hosting/mysql-image/01.sql%E8%AF%AD%E5%8F%A5%E6%98%AF%E5%A6%82%E4%BD%95%E6%89%A7%E8%A1%8C%E7%9A%84,mysql%E7%9A%84%E7%BB%84%E6%88%90%E9%83%A8%E5%88%86%E5%8F%8A%E4%BD%9C%E7%94%A8/MySQL%E7%9A%84%E5%9F%BA%E6%9C%AC%E6%9E%B6%E6%9E%84%E7%A4%BA%E6%84%8F%E5%9B%BE.png)

## 连接器

> **职责**

- 建立连接
- 获取权限
- 维护和管理连接

> **注意事项**

- 一个用户成功建立连接后，即使你用管理员账号对这个用户的权限做了修改，也不会影响已经存在连接的权限。修改完成后，只有再新建的连接才会使用新的权限设置
- 客户端如果太长时间没动静，连接器就会自动将它断开。这个时间是由参数 wait_timeout 控制的，默认值是 8 小时
- MySQL 在执行过程中临时使用的内存是管理在连接对象里面的，在连接断开的时候才释放。如果长连接累积下来，可能导致内存占用太大，被系统强行杀掉（OOM），从现象看就是 MySQL 异常重启了

> **使用建议**

- 使用中要尽量减少建立连接的动作，也就是尽量使用长连接
- 定期断开长连接。使用一段时间，或者程序里面判断执行过一个占用内存的大查询后，断开连接，之后要查询再重连
- MySQL 5.7 或更新版本，可以在每次执行一个比较大的操作后，通过执行 mysql_reset_connection 来重新初始化连接资源。这个过程不需要重连和重新做权限验证，但是会将连接恢复到刚刚创建完时的状态

## 查询缓存

MySQL 拿到一个查询请求后，会先到查询缓存看看，之前是不是执行过这条语句。之前执行过的语句及其结果可能会以 key-value 对的形式，被直接缓存在内存中。key 是查询的语句，value 是查询的结果。如果你的查询能够直接在这个缓存中找到 key，那么这个 value 就会被直接返回给客户端。

**大多数情况下不建议使用查询缓存，为什么呢？**

由查询缓存的失效策略决定的，只要有对一个表的更新，这个表上所有的查询缓存都会被清空。因此，对于更新压力大的表来说，查询缓存的命中率非常低。而对于静态表，即更新频率低的表，例如：配置表，放在外部缓存中更合适，不占用数据库连接资源，且性能更好。

因此，将参数 query_cache_type 设置成 DEMAND，这样对于默认的 SQL 语句都不使用查询缓存。MySQL 8.0 版本直接将查询缓存的整块功能删掉了，也就是说 8.0 开始彻底没有这个功能了。

## 分析器

语法分析，根据语法规则，判断你输入的这个 SQL 语句是否满足 MySQL 语法。如果语句不对，就会收到“You have an error in your SQL syntax”的错误提醒，会提示第一个出现错误的位置，所以你要关注的是紧接“use near”的内容。

## 优化器

优化器是在表里面有多个索引的时候，决定使用哪个索引；或者在一个语句有多表关联（join）的时候，决定各个表的连接顺序。

## 执行器

先判断一下对表有没有执行查询的权限，如果没有，就会返回没有权限的错误。如果有权限，就打开表继续执行。打开表的时候，执行器就会根据表的引擎定义，去使用这个引擎提供的接口。

```mysql
mysql> select * from T where ID=10;
```

- 查询字段没有索引

  ```java
  1. 调用InnoDB引擎接口取这个表的第一行，判断 ID 值是不是 10，如果不是则跳过，如果是则将这行存在结果集中;
  
  2. 调用引擎接口取“下一行”，重复相同的判断逻辑，直到取到这个表的最后一行。 
  
  3. 执行器将上述遍历过程中所有满足条件的行组成的记录集作为结果集返回给客户端。
  ```

- 查询字段有索引

  ```java
  1.第一次调用的是“取满足条件的第一行”这个接口
  
  2.之后循环取“满足条件的下一行”这个接口,接口都是引擎中已经定义好的
  ```

# 事务隔离

## 隔离级别

SQL 标准的事务隔离级别包括：

- 读未提交（read uncommitted）：一个事务还没提交时，它做的变更就能被别的事务看到
- 读提交（read committed）：一个事务提交之后，它做的变更才会被其他事务看到
- 可重复读（repeatable read）：一个事务执行过程中看到的数据，总是跟这个事务在启动时看到的数据是一致的。当然在可重复读隔离级别下，未提交变更对其他事务也是不可见的。
- 串行化（serializable）：顾名思义是对于同一行记录，“写”会加“写锁”，“读”会加“读锁”。当出现读写锁冲突的时候，后访问的事务必须等前一个事务执行完成，才能继续执行。

| 隔离级别         | 脏读 | 不可重复读 | 幻影读 |
| ---------------- | ---- | ---------- | ------ |
| READ-UNCOMMITTED | √    | √          | √      |
| READ-COMMITTED   | ×    | √          | √      |
| REPEATABLE-READ  | ×    | ×          | √      |
| SERIALIZABLE     | ×    | ×          | ×      |

<img src="https://sheungxin.github.io/notpic/ccb1ce3baa39423daff0460f6006e759.png" alt="img" style="zoom:50%;" />

不同的隔离级别下，事务 A 会有哪些不同的返回结果，也就是图里面 V1、V2、V3 的返回值分别是什么。

- 若隔离级别是“读未提交”， 则 V1 的值就是 2。这时候事务 B 虽然还没有提交，但是结果已经被 A 看到了。因此，V2、V3 也都是 2。
- 若隔离级别是“读提交”，则 V1 是 1，V2 的值是 2。事务 B 的更新在提交后才能被 A 看到。所以， V3 的值也是 2。
- 若隔离级别是“可重复读”，则 V1、V2 是 1，V3 是 2。之所以 V2 还是 1，遵循的就是这个要求：事务在执行期间看到的数据前后必须是一致的。
- 若隔离级别是“串行化”，则在事务 B 执行“将 1 改成 2”的时候，会被锁住。直到事务 A 提交后，事务 B 才可以继续执行。所以从 A 的角度看， V1、V2 值是 1，V3 的值是 2。

**MySQL默认是快照读，是不存在幻读的，幻读只有在“当前读”下才会出现。在可重复读的隔离级别下，MySQL通过next-key lock解决“当前读”下幻读问题。**

查看Mysql数据库当前事务隔离级别，默认：REPEATABLE-READ

```mysql
show variables like '%isolation%';
```

> MySQL为什么默认使用REPEATABLE-READ

| session A(READ-COMMITTED) | session B(READ-COMMITTED)  |
| ------------------------- | -------------------------- |
| begin;                    | begin;                     |
| delete from t where a=2;  |                            |
|                           | insert into t values(2,2); |
|                           | commit;                    |
| commit;                   |                            |

MySQL采用WAL预写式日志，提交事务前先后写redo log、binlog，且采用两阶段提交。先预写redo log，再写binlog，最后提交redo log，而binlog只要写成功既可用于从库同步。

根据MySQL日志写入机制可以看出session B提交后binlog一定写成功了，而session A中binlog在commit前什么时刻写成功不确定。如果是在session B提交后写成功，那么session A中binlog一定在session B之后写入。MySQL 5.0之前，binlog只支持statement格式，即sql语句，从库同步得到的binlog中语句如下：

```mysql
insert into t values(2,2);

delete from t where a=2;
```

从库中sql回放顺序和主库完全相反，主从数据不一致。

READ-COMMITTED由于提供了next-key lock，session A执行删除操作时进行了加锁操作，堵塞了session B的插入操作，保证了binlog的写入顺序。因此，MySQL默认将隔离级别设置为可重复读，保证主从复制不出现问题。所以，MySQL 5.0之后，我们也可以采用binlog的row格式+读已提交的隔离级别。

## 启动方式

MySQL 的事务启动方式有以下几种：

- 显式启动事务语句， begin 或 start transaction，配套的提交语句是 commit，回滚语句是 rollback
- set autocommit=0，这个命令会将这个线程的自动提交关掉。意味着如果你只执行一个 select 语句，这个事务就启动了，而且并不会自动提交。这个事务持续存在直到你主动执行 commit 或 rollback 语句，或者断开连接

查看Mysql数据库当前事务启动方式，默认：ON，即autocommit=1

```mysql
show variables like '%autocommit%';
```

建议使用 set autocommit=1，通过显式语句的方式来启动事务，避免长事务

begin/start transaction 命令并不是一个事务的起点，在执行到它们之后的第一个操作 InnoDB 表的语句，事务才真正启动。如果你想要马上启动一个事务，可以使用 start transaction with consistent snapshot 这个命令

## 长事务检测

可以在 information_schema 库的 innodb_trx 表中查询长事务，比如下面这个语句，用于查找持续时间超过 60s 的事务

```mysql
select * from information_schema.innodb_trx where TIME_TO_SEC(timediff(now(),trx_started))>60
```

> 如何避免？

- 确认是否使用了 set autocommit=0？可通过测试环境临时开启general_log查看，或者检测框架参数设置
- 去除只读事务
- 业务连接数据库的时候，根据业务本身的预估，通过 SET MAX_EXECUTION_TIME 命令，来控制每个语句执行的最长时间，避免单个语句意外执行太长时间
- 数据库端监控
  - 监控 information_schema.Innodb_trx 表，设置长事务阈值，超过就报警 / 或者 kill
  - Percona 的 pt-kill 这个工具不错，推荐使用
  - 在业务功能测试阶段要求输出所有的 general_log，分析日志行为提前发现问题
  - 如果使用的是 MySQL 5.6 或者更新版本，把 innodb_undo_tablespaces 设置成 2（或更大的值）。如果真的出现大事务导致回滚段过大，这样设置后清理起来更方便。

# 日志

## WAL

了解MySQL日志前，先要了解WAL(Write-Ahead Loggin)，即预写式日志，其关键点在于先写日志再写磁盘。

在对数据页进行修改时, 通过将"修改了什么"这个操作记录在日志中, 而不必马上将更改内容刷新到磁盘上, 从而将随机写转换为顺序写, 提高了性能。

## binlog

归档日志/逻辑日志，binlog 是 MySQL 的 Server 层实现的，通过追加写入的方式记录，所有引擎都可以使用。

> binlog格式

- statement：记录的是变更的SQL语句
- row：记录的是每行实际数据的变更，8.0下默认选项，建议使用
- mixed：statement和row模式的混合，根据执行的每一条具体的sql语句来区分对待记录的日志形式，也是在statement和row之间选择一种

MySQL 5.0以前，binlog只支持statement格式，这种格式在读已提交(Read Commited)隔离级别下主从复制是有bug的，因此Mysql将可重复读(Repeatable Read)作为默认的隔离级别。

```mysql
-- 查看格式配置
show variables like "%binlog_format%";
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| binlog_format | ROW   |
+---------------+-------+

-- 查看binlog日志，位于data目录下
show binlog events in 'binlog.xxx';

-- 借助 mysqlbinlog 工具解析和查看 binlog 中的内容，start-position用于指定起始位置
mysqlbinlog -vv data/binlog.xxx --start-position=8900 --stop-position=8910;
```

> 写入机制

<img src="https://sheungxin.github.io/notpic/d188d5450413.png" alt="img" style="zoom:50%;" />

每个线程都会分配一块内存binlog cache，参数 binlog_cache_size控制内存的大小。

事务执行过程中，先把日志写到 binlog cache，事务提交的时候，再把 binlog cache 写到 binlog 文件中，并清空 binlog cache。如果事务提交前binlog cache空间不足，还是会暂存到磁盘的。

> **sync_binlog**

write 和 fsync 的时机，是由参数 sync_binlog 控制的：

- 0：默认值。事务提交后，将二进制日志从缓冲写入磁盘，但是不进行刷新操作（fsync()），此时只是写入了操作系统缓冲，若操作系统宕机则会丢失部分二进制日志
- 1：事务提交后，将二进制文件写入磁盘并立即执行刷新操作，相当于是同步写入磁盘，不经过操作系统的缓存
- N：每写N次操作系统缓冲就执行一次刷新操作

sync_binlog建议你设置成 1，这样可以保证 MySQL 异常重启之后 binlog 不丢失

```mysql
-- 查看当前参数设置
show variables like '%log_bin%';
```

> 主要作用

- 备份，用于数据恢复，可使用官方自带工具mysqlbinlog解析binlog日志，进行数据回放
- 复制，用于主从复制
- 第三方场景：解析binlog，增量获取数据库数据，实现数据的订阅&消费

## redo log

redo log称为重做日志，是一种物理日志，记录的是数据页的物理修改。

redo log 是 InnoDB 引擎特有的日志，大小固定，比如可以配置为一组 4 个文件，每个文件的大小是 1GB。从头开始写，写到末尾就又回到开头循环写，如下面这个图所示：

<img src="https://sheungxin.github.io/notpic/1031a5b226dd472e82572763d693934c.png" alt="img" style="zoom:50%;" />

> 好处

- 高效：数据变更记录在redo log中（在某个数据页上做了什么修改），并更新内存即可，空闲时刷新磁盘
- **crash-safe**：有了 redo log，InnoDB 就可以保证即使数据库发生异常重启，之前提交的记录都不会丢失（设置innodb_flush_log_at_trx_commit=1，表示每次事务的 redo log 都直接持久化到磁盘）

> 执行流程

<img src="https://sheungxin.github.io/notpic/526a60f34ff64818b8450409c53fbf44.png" alt="img" style="zoom:50%;" />

**redo log 和 binlog 是怎么关联起来的?**

它们有一个共同的数据字段，叫 XID。崩溃恢复的时候，会按顺序扫描 redo log：

- 如果碰到既有 prepare、又有 commit 的 redo log，就直接提交；
- 如果碰到只有 prepare、而没有 commit 的 redo log，就拿着 XID 去 binlog 找对应的事务

**崩溃恢复时的判断规则？**

- 如果 redo log 里面的事务是完整的，也就是已经有了 commit 标识，则直接提交

- 如果 redo log 里面的事务只有完整的 prepare，则判断对应的事务 binlog 是否存在并完整
  - 如果是，则提交事务
  - 否则，回滚事务

**prepare 和 commit两阶段提交的好处？**

保持两份日志之间的逻辑一致性，binlog用于备库的同步与恢复时，不一致会造成主从同步一致性问题。例如：

- 先写redo log，后写binlog：binlog可能存在丢失，造成从库数据少于主库
- 先写binlog，后写redo log：redo log可能存在丢失，造成从库数据多于主库

> innodb_flush_log_at_trx_commit

![img](https://img2020.cnblogs.com/blog/1334255/202004/1334255-20200414103201088-1760773510.png)

Redo Log Buffer用于事务提交前存放redo log，提交一个事务，会根据一定的策略把 redo 日志从 redo log buffer 里刷入到磁盘文件里去，通过innodb_flush_log_at_trx_commit 来配置，选项如下：

- 值为0：提交事务的时候，不立即把 redo log buffer 里的数据刷入磁盘文件的，而是依靠 InnoDB 的主线程每秒执行一次刷新到磁盘。提交事务时 mysql 宕机，可能造成内存里的数据丢失
- 值为1 : 提交事务的时候，就必须把 redo log 从内存刷入到磁盘文件里去，只要事务提交成功，那么 redo log 就必然在磁盘里了。注意，因为操作系统的“延迟写”特性，此时的刷入只是写到了操作系统的缓冲区中，因此执行同步操作才能保证一定持久化到了硬盘中。
- 值为2 : 提交事务的时候，把 redo 日志写入磁盘文件对应的 os cache 缓存里去，而不是直接进入磁盘文件，可能 1 秒后才会把 os cache 里的数据写入到磁盘文件里去。

因此，只有1才能真正地保证事务的持久性，但是由于刷新操作 fsync() 是阻塞的，直到完成后才返回，我们知道写磁盘的速度是很慢的，因此 MySQL 的性能会明显地下降。如果不在乎事务丢失，0和2能获得更高的性能。

```mysql
select @@innodb_flush_log_at_trx_commit;
```

**真实数据落盘与redo log无关，写redo log前数据已写入buffer poll中，崩溃恢复也是先写入buffer poll，真正的落盘是从buffer poll中发起的**

## undo log

回滚日志，是一种逻辑日志，提供回滚和多个行版本控制(MVCC)。

在 MySQL 中，实际上每条记录在更新的时候都会同时记录一条回滚操作，记录上的最新值，通过回滚操作，都可以得到前一个状态的值。

假设一个值从 1 被按顺序改成了 2、3、4，在回滚日志里面就会有类似下面的记录（反向记录）

<img src="https://sheungxin.github.io/notpic/d8a7cd9990f9462d9aa76888a7d5e93d.png" alt="img" style="zoom:50%;" />

当系统里没有比这个回滚日志更早的 read-view 的时候，即没有事务再需要用到这些回滚日志时，回滚日志会被删除。因此，建议尽量不要使用长事务。

在 MySQL 5.5 及以前的版本，回滚日志是跟数据字典一起放在 ibdata 文件里的，即使长事务最终提交，回滚段被清理，文件也不会变小。

在MySQL5.6中开始支持把undo log分离到独立的表空间，并放到单独的文件目录下。可通过innodb_undo_tablespaces设定创建的undo表空间的个数，在mysql_install_db时初始化后，就再也不能被改动了，修改该值会导致MySQL无法启动。默认值为0，表示不独立设置undo的tablespace，默认记录到ibdata中；否则，则在undo目录下创建多个undo文件(每个文件的默认大小为10M)，最多可以设置到126。

## relay log

<img src="https://sheungxin.github.io/notpic/88bac74acf4643aaa73ea3f626d1204c.png" alt="img" style="zoom:50%;" />

relay log，称为中转日志，sql_thread 读取中转日志，解析出日志里的命令，并执行

主从同步机制有：

- 全同步复制：在主节点上写入的数据，在从服务器上都同步完了以后才会给客户端返回成功消息，相对来说比较安全，但是耗时较长
- 异步复制：master不需要保证slave接收并执行了binlog，能够保证master最大性能。但是slave可能存在延迟，主备数据无法保证一致性，在不停服务的前提下如果master宕机，提升slave为新的主库，就会丢失数据。
- 半同步复制：存在主从延迟，开启并行复制（库级别并行，并行读取relay log中不同库的日志，然后并行重放不同库的日志）
  - 主库写入binlog，强制立即将数据同步到从库
  - 从库将日志写入自己本地的relay log后返回一个ack给主库
  - 主库收到至少一个从库ack之后认为写操作成功

## general log

开启 general log 会将所有到达MySQL Server的SQL语句记录下来。一般不会开启开功能，因为log的量会非常庞大。但个别情况下可能会临时的开一会儿general log以供排障使用。 相关参数一共有：general_log、log_output、general_log_file

```mysql
show variables like 'general_log'; -- 查看日志是否开启

set global general_log=on; -- 开启日志功能

show variables like 'general_log_file'; -- 看看日志文件保存位置

set global general_log_file='tmp/general.lg'; -- 设置日志文件保存位置

show variables like 'log_output'; -- 看看日志输出类型 table或file

set global log_output='table'; -- 设置输出类型为table，对应表mysql.slow_log

set global log_output='file'; -- 设置输出类型为file，默认类型
```

## 慢日志

```mysql
mysql> show VARIABLES like 'slow_query%';
+---------------------+----------------------------------------------------+
| Variable_name       | Value                                              |
+---------------------+----------------------------------------------------+
| slow_query_log      | OFF                                                |
| slow_query_log_file | D:\tools\mysql-8.0.11-winx64\data\user-PC-slow.log |
+---------------------+----------------------------------------------------+

-- 开启慢日志(重启失效)
set GLOBAL slow_query_log=on

-- 查看当前慢日志阈值
select @@long_query_time; -- 等价于：show variables like '%long_query_time%';

-- 设置慢日志阈值
set long_query_time=0;
```

**mysqldumpslow**：mysql官方提供的慢查询日志分析工具，统计不同慢sql的

- 出现次数(Count)
- 执行最长时间(Time)
- 累计总耗费时间(Time)
- 等待锁的时间(Lock)
- 发送给客户端的行总数(Rows)
- 扫描的行总数(Rows)
- 用户以及sql语句本身(抽象了一下格式, 比如 limit 1, 20 用 limit N,N 表示)

# MVCC

InnoDB 里面每个事务有一个唯一的事务 ID，叫作 transaction id。它是在事务开始的时候向 InnoDB 的事务系统申请的，是按申请顺序严格递增的。

每行数据有多个版本，每次事务更新数据的时候，都会生成一个新的数据版本，并且把 transaction id 赋值给这个数据版本的事务 ID，记为 row trx_id。同时，旧的数据版本要保留，并且在新的数据版本中，可以直接拿到它。

<img src="https://sheungxin.github.io/notpic/529270ade1514b1b8d9f5e5f9cbde3a5.png" alt="img" style="zoom:50%;" />

上图中三个虚线箭头，即U1、U2、U3就是 undo log，而V1、V2、V3 并不是物理上真实存在的，而是每次需要的时候根据当前版本和 undo log 计算出来的

> 快照是基于整库的，如何构建的？

按照可重复读的定义，一个事务启动的时候，能够看到所有已经提交的事务结果，但是之后的事务执行期间，其他事务的更新对它不可见。

<img src="https://sheungxin.github.io/notpic/9c8d89aa10ca4f35bed73e8fbb115f96.png" alt="img" style="zoom:50%;" />

在实现上， InnoDB 为每个事务构造了一个数组，用来保存这个事务启动瞬间，当前正在“活跃”的所有事务 ID，即启动了但还没提交的事务ID，对应上图中黄色部分。这个数组对应两个概念：

- 低水位：数组里面事务ID最小值
- 高水位：**当前系统里面已经创建过的事务 ID 的最大值加 1 记为高水位**

由视图数组和高水位，组成了当前事务的一致性视图（read-view），而数据版本的可见性规则，就是**基于数据的 row trx_id 和这个一致性视图的对比**结果得到的，如下所示：

- 如果落在绿色部分，即小于低水位，表示这个版本是已提交的事务或者是当前事务自己生成的，这个数据是可见的；
- 如果落在红色部分，即大于等于高水位，表示这个版本是由将来启动的事务生成的，是肯定不可见的；
- 如果落在黄色部分，那就包括两种情况：
  - 若 row trx_id 在数组中，表示这个版本是由还没提交的事务生成的，不可见
  - 若 row trx_id 不在数组中，表示这个版本是已经提交了的事务生成的，可见

```mysql
-- 假设存在事务T1,T2,T4,T7,T8,T9，其中T2,T4,T8活跃状态，此刻启动事务A

-- 事务A的视图数组viewA如下
viewA = [T2,T4,T8]

-- 低水位
lowLevel = T2
    
-- 高水位
highLevel = T9 + 1
    
-- T1：T1 < T2，即处于绿色部分，对于事务A可见
-- T11：T11 > T10，即处于红色部分，对于事务A不可见
-- T4：T4 > T2 && T4 < T10，即处于黄色部分，且存在viewA中，说明未提交不可见
-- T7：T7 > T2 && T7 < T10，即处于黄色部分，但不存在viewA中，说明已提交可见
```

**MVCC只在读已提交和可重复读两个隔离级别下工作**，两者的差异在于：

- 读已提交每次读取都会创建一个新的read-view
- 可重复读在同一个事务中共享同一个read-view

# buffer pool

## 什么是buffer poll？

![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeGJpYmVZNFVRdkxqakc3NmRJc2JYWUdJVDRRaWJXMlhxV0lFalRSZ1R4RklzeldaQ1k4eUNadFpvS01haWNIR2ZZUjJUZW9XQzBzZ1FnQS82NDA?x-oss-process=image/format,png)

缓冲池，缓存表数据与索引数据，把磁盘上的数据加载到缓冲池，避免每次访问都进行磁盘IO，起到加速访问的作用。

磁盘是按页读取，一次至少读取一页数据(一般是4K)。数据访问通常都遵循“集中读写”的原则，使用一些数据，大概率会使用附近的数据，这就是所谓的“局部性原理”，它表明提前加载是有效的，确实能够减少磁盘IO。

InnoDB的缓冲池一般也是按页读取数据，存储结构如下：

![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeTI5MWlhaWIyb3NSYlNPaWNZRzMwTWFLOUswRHBuNTh3a0tPWHJaTmZXb25FNE5BdW1SOU9LQ0F4dGE1SGdmM21pYzdRQmJzN1FDaWFkRmVBLzY0MA?x-oss-process=image/format,png)

- 新老生代收尾相连，很好的解决了“预读失败”的问题
  - 首次读取从老生代头部插入，如果一直不被再次读取，即预读失败，按照LRU淘汰策略，会比新生代数据更早淘汰出缓冲池
  - 如果老生代数据被再次读取，会被加入新生代头部。如果后续不被使用，按照LRU淘汰策略，向后逐步移动到老生代直到尾部被移除
- 老生代停留时间窗口，很好的解决了缓存池污染的问题

```mysql
select * from user where name like "%shenjian%";

-- 不满足最左匹配，不能命中索引，必须全表扫描，需要访问大量数据页，步骤如下： 
-- 1. 把页加载到缓冲池，插入到老生代头部
-- 2. 从页中读取相关的row进行过滤，这时会把数据插入新生代头部
-- 综上，所有的数据都会加载到新生代头部，且只会访问一次，真正的热数据被大量换出

-- 如果加上“老生代停留时间窗口”T，只有满足“被访问”且“在老生代停留时间”大于T，才会放入新生代头部
```

## 参数设置

```mysql
-- 不同版本参数有变化，以下基于8.0.26
mysql> show variables like 'innodb_buffer_pool%';
+-------------------------------------+----------------+
| Variable_name                       | Value          |
+-------------------------------------+----------------+
-- 缓冲池增加或减少innodb_buffer_pool_size时，操作以块（chunk）形式执行 
| innodb_buffer_pool_chunk_size       | 134217728      | -- 128M
-- 在MySQL服务器关闭时是否记录在InnoDB缓冲池中缓存的页面，以便在下次重新启动时缩短预热过程
| innodb_buffer_pool_dump_at_shutdown | ON             | 
-- 立刻记录在InnoDB缓冲池中缓存的页面
| innodb_buffer_pool_dump_now         | OFF            |
-- 按比例持久化每个缓冲池实例最近使用的页面，例如：每个缓冲池100个page，默认dump每个缓冲池最近使用的25个page
| innodb_buffer_pool_dump_pct         | 25             |
-- 缓冲池中的热数据持久化的文件名，默认文件名为ib_buffer_pool，位于datadir下，默认basedir/data下
| innodb_buffer_pool_filename         | ib_buffer_pool |
-- 可以设置为OFF，用于将innodb buffer pool从coredump中排除，用于减小coredump的体积
| innodb_buffer_pool_in_core_file     | ON             |
-- 缓冲池实例数，可提高并发性能。innodb_buffer_pool_size大于1G时生效，因此，建议每个不小于1GB
| innodb_buffer_pool_instances        | 1              |
-- 中断由innodb_buffer_pool_load_at_startup或innodb_buffer_pool_load_now触发的缓冲池内容恢复过程
| innodb_buffer_pool_load_abort       | OFF            |
-- MySQL服务器启动时，通过加载先前保存的数据实现自动预热，通常与innodb_buffer_pool_dump_at_shutdown结合使用
| innodb_buffer_pool_load_at_startup  | ON            |
-- 立即通过加载一组数据页面来加热缓冲池，通常与innodb_buffer_pool_dump_now一起使用
| innodb_buffer_pool_load_now         | OFF            |
-- 1.缓冲池的大小，允许动态调整，必须是：innodb_buffer_pool_chunk_size*innodb_buffer_pool_instances的倍数，如果不是自动调整
-- 2.建议调大这个参数，在专用数据库服务器上，可以将缓冲池大小设置为服务器物理内存的80%
| innodb_buffer_pool_size             | 134217728      | -- 128M 
+-------------------------------------+----------------+


mysql> show variables like '%innodb_old_blocks_time%';
+------------------------+-------+
| Variable_name          | Value |
+------------------------+-------+
-- 老生代占整个LRU链长度的比例，默认是37，即整个LRU中新生代与老生代长度比例是63:37
| innodb_old_blocks_pct  | 37    |
-- 老生代停留时间窗口，默认1s，即同时满足“被访问”与“在老生代停留时间超过1秒”两个条件，才会被插入到新生代头部
| innodb_old_blocks_time | 1000  | 
+------------------------+-------+
```

## change buffer

毫无疑问，对于读请求，缓冲池能够减少磁盘IO，提升性能。问题来了，**那写请求呢？**

**change buffer**：在**非唯一普通索引页**(non-unique secondary index page)不在缓冲池中，对页进行了写操作，并不会立刻将磁盘页加载到缓冲池，而仅仅记录缓冲变更(buffer changes)，等未来数据被读取时，再将数据合并(merge)恢复到缓冲池中的技术，降低写操作的磁盘IO，提升数据库性能。



|                       修改页在缓冲池内                       |                      修改页不在缓冲池内                      |             修改页不在缓冲池内-change buffer优化             |
| :----------------------------------------------------------: | :----------------------------------------------------------: | :----------------------------------------------------------: |
| ![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeGJpYmVZNFVRdkxqakc3NmRJc2JYWUd6MXZYY2x6UFp4MmppYlhwQ0lkdFNvWHNhbncwM2ZpYkRXQUdrTWhpYTJQMXdOTkRCVVB1cGlhWkFRLzY0MA?x-oss-process=image/format,png) | ![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeGJpYmVZNFVRdkxqakc3NmRJc2JYWUczUzlRRVZpY1owQWlheHduMVBqUmdSY2xJbU1keTNPYUQzUGVUUUd2eWF2aWN1d2d5WUJocVkybHcvNjQw?x-oss-process=image/format,png) | ![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeGJpYmVZNFVRdkxqakc3NmRJc2JYWUdLdDhrUHhtVW9wTVRCRFJzWFBBUk5vVWJ4OUVJUUZqbWliYTdpYXhhbWNyOEliZ0dYRWZjd1V0US82NDA?x-oss-process=image/format,png) |

根据以上三幅对比图，当修改页不在缓冲池内时，使用change buffer可以减少一次磁盘读取操作，与修改页在缓冲池近似

>  如果此时有请求查询索引页40的数据，如何处理？

![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6X3BuZy9ZcmV6eGNraFlPeGJpYmVZNFVRdkxqakc3NmRJc2JYWUd0NEZtZVM0NENYRGIxNU5UUU5uSUxVa0xmWUhsNTJ6SmZhTGlibmlhaWNkVGpVT1M5NHhremVJZXcvNjQw?x-oss-process=image/format,png)

- 载入索引页，缓冲池未命中，这次磁盘IO不可避免
- 从写缓冲读取相关信息
- 恢复索引页，放到缓冲池LRU里

> 什么时候才会触发写缓冲数据合并？

- 数据页被访问
- 数据库空闲，后台线程触发
- 数据库缓冲池不够用
- 数据库正常关闭时
- redo log写满时

> 写缓冲机制适用场景

非唯一索引且写多读少

> 参数设置

```mysql
mysql> show variables like '%innodb_change_buffer_%';
+-------------------------------+-------+
| Variable_name                 | Value |
+-------------------------------+-------+
-- 配置写缓冲的大小，占整个缓冲池的比例，默认值是25%，最大值是50%
| innodb_change_buffer_max_size | 25    |
-- 配置哪些写操作启用写缓冲，可以设置成all/none/inserts/deletes等
| innodb_change_buffering       | all   |
+-------------------------------+-------+
```

> change buffer 与 redo log

```mysql
CREATE TABLE `t` (
`id` int(11) NOT NULL,
`k` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `index_k` (`k`) USING BTREE
) ENGINE=InnoDB;
```

|         insert into t(id,k) values(id1,k1),(id2,k2)          |             select * from t where k in (k1, k2)              |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
| ![img](https://upload-images.jianshu.io/upload_images/4930604-9622202aa0396752.png?imageMogr2/auto-orient/strip) | ![img](https://upload-images.jianshu.io/upload_images/4930604-3e343e899188ac99.png?imageMogr2/auto-orient/strip) |

- redo log 主要节省的是随机写磁盘的 IO 消耗（转成顺序写）
- change buffer 主要节省的则是随机读磁盘的 IO 消耗

## 脏页、干净页

**当内存数据页跟磁盘数据页内容不一致的时候，我们称这个内存页为“脏页”。内存数据写入到磁盘后，内存和磁盘上的数据页的内容就一致了，称为“干净页”**。

当MySQL 偶尔“抖”一下的那个瞬间，可能就是在刷脏页（flush），场景如下：

- redo log写满了，尽量避免，此种情况，系统不能再接受更新（此处只是触发了buffer poll的flush，redo log没有能力落盘）
- 系统内存不足，当需要新的内存页，淘汰数据页之前，需要把脏页写到磁盘
- 系统空闲
- Mysql正常关闭

脏页刷新需要考虑的因素：

- 脏页比例： innodb_max_dirty_pages_pct，默认75%
- 写盘速度：innodb_io_capacity

# 索引

## 索引模型

- 哈希表
  - 适用于只有等值查询的场景，Memory引擎默认索引
  - InnoDB支持自适应哈希索引，不可干预，由引擎自行决定是否创建
- 有序数组：在等值查询和范围查询场景中的性能都非常优秀，但插入和删除数据需要进行数据移动，成本太高。因此，只适用于静态存储引擎
- 二叉平衡树：每个节点的左儿子小于父节点，父节点又小于右儿子，时间复杂度是 O(log(N))
- 多叉平衡树：索引不止存在内存中，还要写到磁盘上。为了让一个查询尽量少地读磁盘，就必须让查询过程访问尽量少的数据块。因此，要使用“N 叉”树。

## B+Tree

> B-Tree 与 B+Tree

- B-Tree

![B-Tree](https://img-blog.csdn.net/20160202204827368)

- B+Tree

![B+Tree](https://img-blog.csdn.net/20160202205105560)

InnoDB 使用了 B+ 树索引模型。假设，我们有一个主键列为 ID 的表，表中有字段 k，并且在 k 上有索引，如下所示：

<img src="https://sheungxin.github.io/notpic/d8d77cd09a074a638644fadf0a4d2286.png" alt="img" style="zoom:50%;" />

- 主键索引：也被称为聚簇索引，叶子节点存的是整行数据
- 非主键索引：也被称为二级索引，叶子节点内容是主键的值

> 注意事项

- 索引基于数据页有序存储，可能发生数据页的分裂(页存储空间不足)和合并(数据删除造成页利用率低)
- 数据的无序插入会造成数据的移动，甚至数据页的分裂
- 主键长度越小，普通索引的叶子节点就越小，普通索引占用的空间也就越小
- 索引字段越小，单层可存储数据量越多，可减少磁盘IO

```java
// 假设一个数据页16K、一行数据1K、索引间指针6字节、索引字段bigint类型(8字节)

// 索引个数
K = 16*1024/(8+6) =1170

// 单个叶子节点记录数
N = 16/1 = 16

// 三层B+记录数
V = K*K*N = 21902400
```

**MyISAM也是使用B+Tree索引，区别在于不区分主键和非主键索引，均是非聚簇索引，叶子节点保存的是数据文件的指针**

## 索引选择

优化器选择索引的目的，是找到一个最优的执行方案，并用最小的代价去执行语句。在数据库里面，扫描行数是影响执行代价的因素之一。扫描的行数越少，意味着访问磁盘数据的次数越少，消耗的 CPU 资源越少。

当然，扫描行数并不是唯一的判断标准，优化器还会结合是否使用临时表、是否排序等因素进行综合判断。

> 扫描行数如何计算

一个索引上不同的值越多，这个索引的区分度就越好。而一个索引上不同的值的个数，称之为“基数”（cardinality）。

```mysql
-- 查看当前索引基数
mysql> show index from test;
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| Table | Non_unique | Key_name | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment |
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| test  |          0 | PRIMARY  |            1 | id          | A         |      100256 | NULL     | NULL   |      | BTREE      |         |               |
| test  |          1 | index_a  |            1 | a           | A         |      98199  | NULL     | NULL   | YES  | BTREE      |         |               |
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
```

从性能的角度考虑，InnoDB 使用**采样统计**，默认会选择 N 个数据页，统计这些页面上的不同值，得到一个平均值，然后乘以这个索引的页面数，就得到了这个索引的基数。因此，上述两个索引显示的基数并不相同。

而数据表是会持续更新的，索引统计信息也不会固定不变。所以，当变更的数据行数超过 1/M 的时候(innodb_stats_persistent=on时默认10，反之16)，会自动触发重新做一次索引统计。

```mysql
mysql> show variables like '%innodb_stats_persistent%';
+--------------------------------------+-------------+
| Variable_name                        | Value       |
+--------------------------------------+-------------+
-- 是否自动触发更新统计信息，当被修改的数据超过10%时就会触发统计信息重新统计计算
| innodb_stats_auto_recalc             | ON          |
-- 控制在重新计算统计信息时是否会考虑删除标记的记录
| innodb_stats_include_delete_marked   | OFF         |
-- 对null值的统计方法，当变量设置为nulls_equal时，所有NULL值都被视为相同
| innodb_stats_method                  | nulls_equal | 
-- 操作元数据时是否触发更新统计信息
| innodb_stats_on_metadata             | OFF         |
-- 统计信息是否持久化存储
| innodb_stats_persistent              | ON          |
-- innodb_stats_persistent=on，持久化统计信息采样的抽样页数
| innodb_stats_persistent_sample_pages | 20          |
-- 不推荐使用，已经被innodb_stats_transient_sample_pages替换
| innodb_stats_sample_pages            | 8           |
-- 瞬时抽样page数
| innodb_stats_transient_sample_pages  | 8           |
+--------------------------------------+-------------+
```

- 除了因为抽样导致统计基数不准外，MVCC也会导致基数统计不准确。例如：事务A先事务B开启且未提交，事务B删除部分数据，在可重复读中事务A还可以查询到删除的数据，此部分数据目前至少有两个版本，有一个标识为deleted的数据。

- 主键是直接按照表的行数来估计的，表的行数，优化器直接使用`show table status like 't'`的值

- 手动触发索引统计：

```mysql
-- 重新统计索引信息
mysql> analyze table t;
```

> 排序对索引选择的影响

```mysql
-- 创建表
mysql> CREATE TABLE `t` (
`id` int(11) NOT NULL,
`a` int(11) DEFAULT NULL,
`b` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `a` (`a`),
KEY `b` (`b`)
) ENGINE=InnoDB;

-- 定义测试数据存储过程
mysql> delimiter ;
CREATE PROCEDURE idata ()
BEGIN

DECLARE i INT ;
SET i = 1 ;
WHILE (i <= 100000) DO
	INSERT INTO t
VALUES
	(i, i, i) ;
SET i = i + 1 ;
END
WHILE ;
END;
delimiter ;

-- 执行存储过程，插入测试数据
mysql> CALL idata ();

-- 查看执行计划，使用了字段a上的索引
mysql> explain select * from t where a between 10000 and 20000;
+----+-------------+-------+-------+---------------+-----+---------+------+-------+-----------------------+
| id | select_type | table | type  | possible_keys | key | key_len | ref  | rows  | Extra                 |
+----+-------------+-------+-------+---------------+-----+---------+------+-------+-----------------------+
|  1 | SIMPLE      | t     | range | a             | a   | 5       | NULL | 10000 | Using index condition |
+----+-------------+-------+-------+---------------+-----+---------+------+-------+-----------------------+

-- 由于需要进行字段b排序，虽然索引b需要扫描更多的行数，但本身是有序的，综合扫描行数和排序，优化器选择了索引b，认为代价更小
mysql> explain select * from t where (a between 1 and 1000) and (b between 50000 and 100000) order by b limit 1;
+----+-------------+-------+-------+---------------+-----+---------+------+-------+------------------------------------+
| id | select_type | table | type  | possible_keys | key | key_len | ref  | rows  | Extra                              |
+----+-------------+-------+-------+---------------+-----+---------+------+-------+------------------------------------+
|  1 | SIMPLE      | t     | range | a,b           | b   | 5       | NULL | 50128 | Using index condition; Using where |
+----+-------------+-------+-------+---------------+-----+---------+------+-------+------------------------------------+

-- 方案1：通过force index强制走索引a，纠正优化器错误的选择，不建议使用（不通用，且索引名称更变语句也需要变）
mysql> explain select * from t force index(a) where (a between 1 and 1000) and (b between 50000 and 100000) order by b limit 1;
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+
| id | select_type | table | type  | possible_keys | key | key_len | ref  | rows | Extra                                              |
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+
|  1 | SIMPLE      | t     | range | a             | a   | 5       | NULL |  999 | Using index condition; Using where; Using filesort |
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+

-- 方案2：引导 MySQL 使用我们期望的索引，按b,a排序，优化器需要考虑a排序的代价
mysql> explain select * from t where (a between 1 and 1000) and (b between 50000 and 100000) order by b,a limit 1;
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+
| id | select_type | table | type  | possible_keys | key | key_len | ref  | rows | Extra                                              |
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+
|  1 | SIMPLE      | t     | range | a,b           | a   | 5       | NULL |  999 | Using index condition; Using where; Using filesort |
+----+-------------+-------+-------+---------------+-----+---------+------+------+----------------------------------------------------+

-- 方案3：有些场景下，我们可以新建一个更合适的索引，来提供给优化器做选择，或删掉误用的索引
ALTER TABLE `t`
DROP INDEX `a`,
DROP INDEX `b`,
ADD INDEX `ab` (`a`,`b`) ;
```

## 索引优化

### 索引选择性

**索引选择性 = 基数 / 总行数**

```mysql
-- 表t中字段xxx的索引选择性
select count(distinct xxx)/count(id) from t;
```

索引的选择性，指的是不重复的索引值（基数）和表记录数的比值。选择性是索引筛选能力的一个指标，索引的取值范围是 0~1 ，当选择性越大，索引价值也就越大。

**在使用普通索引查询时，会先加载普通索引，通过普通索引查询到实际行的主键，再使用主键通过聚集索引查询相应的行，以此循环查询所有的行。若直接全量搜索聚集索引，则不需要在普通索引和聚集索引中来回切换，相比两种操作的总开销可能扫描全表效率更高。**

实际工作中，还是要看业务情况，如果数据分布不均衡，实际查询条件总是查询数据较少的部分，在索引选择较低的列上加索引，效果可能也很不错。

### 覆盖索引

覆盖索引可以减少树的搜索次数，显著提升查询性能，所以使用覆盖索引是一个常用的性能优化手段

<img src="https://sheungxin.github.io/notpic/d8d77cd09a074a638644fadf0a4d2286.png" alt="img" style="zoom:50%;" />

```mysql
-- 只需要查 ID 的值，而 ID 的值已经在 k 索引树上了，因此可以直接提供查询结果，不需要回表
select ID from T where k between 3 and 5

-- 增加字段V，每次查询需要返回V，可考虑把k、v做成联合索引
select ID,V from T where k between 3 and 5
```

### 最左前缀原则+索引下推

```mysql
-- id、name、age三列，name、age上创建联合索引

-- 满足最左前缀原则，name、age均走索引
select * from T where name='xxx' and age=12

-- Mysql自动优化，调整name、age顺序，，name、age均走索引
select * from T where age=12 and name='xxx'

-- name满足最左前缀原则走索引，MySQL5.6引入索引下推优化（index condition pushdown)，即索引中先过滤掉不满足age=12的记录再回表
select * from T where name like 'xxx%' and age=12

-- 不满足最左前缀原则，均不走索引
select * from T where name like '%xxx%' and age=12

-- 满足最左前缀原则，name走索引
select * from T where name='xxx'

-- 不满足最左前缀原则，不走索引
select * from T where age=12
```

联合索引建立原则：

- 如果通过调整顺序，可以少维护一个索引，那么这个顺序往往就是需要优先考虑采用的
- 空间：优先小字段单独建立索引，例如：name、age，可建立(name,age)联合索引和(age)单字段索引

### 前缀索引

```mysql
mysql> create table SUser(
ID bigint unsigned primary key,
name  varchar(64),   
email varchar(64),
...
)engine=innodb;

-- 以下查询场景
mysql> select name from SUser where email='xxx';

-- 方案1：全文本索引，回表次数由符合条件的数据量决定
mysql> alter table SUser add index index1(email);

-- 方案2：前缀索引，回表次数由前缀匹配结果决定
mysql> alter table SUser add index index2(email(6));
```

前缀索引可以节省空间，但需要注意前缀长度的定义，在节省空间的同时，不能增加太多查询成本，即减少回表验证次数

> 如何设置合适的前缀长度？

```mysql
-- 预设一个可以接受的区分度损失比，选择满足条件中最小的前缀长度
select count(distinct left(email,n))/count(distinct email) from SUser;
```

> 如果合适的前缀长度较长？

比如身份证号，如果满足区分度要求，可能需要12位以上的前缀索引，节约的空间有限，又增加了查询成本，就没有必要使用前缀索引。此时，我们可以考虑使用以下方式：

- 倒序存储

```mysql
-- 查询时字符串反转查询
mysql> select field_list from t where id_card = reverse('input_id_card_string');
```

- 使用hash字段

  ```mysql
  -- 创建一个整数字段，来保存身份证的校验码，同时在这个字段上创建索引
  mysql> alter table t add id_card_crc int unsigned, add index(id_card_crc);
  
  -- 查询时使用hash字段走索引查询，再使用原字段精度过滤
  mysql> select field_list from t where id_card_crc=crc32('input_id_card_string') and id_card='input_id_card_string'
  ```

以上两种方式的缺点：

- 不支持范围查询
- 使用hash字段需要额外占用空间，新增了一个字段
- 读写时需要额外的处理，reverse或者crc32等

> 前缀索引对覆盖索引的影响？

```mysql
-- 使用前缀索引就用不上覆盖索引对查询性能的优化
select id,email from SUser where email='xxx';
```

### 唯一索引

建议使用普通索引，唯一索引无法使用change buffer，内存命中率低

### 索引失效

- 不做列运算，包括函数的使用，可能破坏索引值的有序性
- 避免 `%xxx` 式查询使索引失效
- or语句前后没有同时使用索引，当or左右查询字段只有一个是索引，该索引失效
- 组合索引ABC问题，最左前缀原则
- 隐式类型转化
- 隐式字符编码转换
- 优化器放弃索引，回表、排序成本等因素影响，改走其它索引或者全部扫描

# 锁

## 全局锁

全局锁就是对整个数据库实例加锁。MySQL 提供了一个加全局读锁的方法FTWRL

```mysql
Flush tables with read lock
```

全局锁的典型使用场景是，做全库逻辑备份，也就是把整库每个表都 select 出来存成文本。在备份过程中整个库完全处于只读状态，存在以下问题：

- 如果你在主库上备份，那么在备份期间都不能执行更新，业务基本上就得停摆
- 如果你在从库上备份，那么备份期间从库不能执行主库同步过来的 binlog，会导致主从延迟

可使用官方自带的逻辑备份工具mysqldump，配合参数–single-transaction，导数据之前启动一个事务，来确保拿到一致性视图。由于 MVCC 的支持，这个过程中数据是可以正常更新的。但需要注意的是：single-transaction 方法只适用于所有的表使用事务引擎的库(InnoDB )

## 表级锁

- 表锁

    ```mysql
    -- 给指定表加上表级读锁或写锁
    lock tables … read/write

    -- 查看表锁定情况
    -- In_use：表上锁及请求锁的数量(表锁时其他会话写请求堵塞)
    -- Name_locked：表名是否被锁定，用于删除表和表重命名
    show open tables where in_use >=1;
    | Database | Table | In_use | Name_locked |
    +----------+-------+--------+-------------+
    | test     | t     |      1 |           0 |

    -- 释放被当前会话持有的任何锁
    unlock tables
    ```

- 元数据锁

  MDL（metadata lock)，在 MySQL 5.5 版本中引入了 MDL，当对一个表做增删改查操作的时候，加 MDL 读锁；当要对表做结构变更操作的时候，加 MDL 写锁。

<img src="https://sheungxin.github.io/notpic/ea20d4f08ad6441db12879b13520956f.jpeg" alt="img" style="zoom:50%;" />

上图中如果session A事务未及时提交，就会一直占用MDL锁，session C中MDL写锁堵塞，后续的读请求因为MDL读锁堵塞，造成整个表不可读写。如果刚好是一张热点表，就有可能造成数据库线程爆满，从而整个库不可用。因此，对于长事务或者热点表的结构调整要慎重。

- 意向锁

  意向锁是一种不与行级锁冲突的表级锁，分为两种：

  - 意向共享锁（intention shared lock, IS）：事务有意向对表中的某些行加共享锁（S锁）

    ```mysql
    -- 事务要获取某些行的 S 锁，必须先获得表的 IS 锁。
    SELECT column FROM table ... LOCK IN SHARE MODE;
    ```

  - 意向排他锁（intention exclusive lock, IX）：事务有意向对表中的某些行加排他锁（X锁）

    ```mysql
    -- 事务要获取某些行的 X 锁，必须先获得表的 IX 锁。
    SELECT column FROM table ... FOR UPDATE;
    ```

  **意向锁是由数据引擎自己维护的，用户无法手动操作意向锁**，在为数据行加共享 / 排他锁之前，InooDB 会先获取该数据行所在数据表对应意向锁。

  其存在的意义在于：对同一张表加表锁时，只需要检测是否存在意向排他锁即可，不用检测表中行上的排他锁存在。

  |             | 意向共享锁（IS） | 意向排他锁（IX） |
  | :---------: | :--------------: | :--------------: |
  | 共享锁（S） |       兼容       |       互斥       |
  | 排他锁（X） |       互斥       |       互斥       |

  **注意：这里的排他 / 共享锁指的都是表锁！！！意向锁不会与行级的共享 / 排他锁互斥！！！意向锁之间是互相兼容的！！！**

## 行锁

行锁又称记录锁，记为LOCK_REC_NOT_GAP

```mysql
-- 加共享锁(Shared Locks：S锁)
select…lock in share mode

-- 加排他锁(Exclusive Locks：X锁)
select…for update
```

> 两阶段锁协议

在 InnoDB 事务中，行锁是在需要的时候才加上的，但并不是不需要了就立刻释放，而是要等到事务结束时才释放。因此，如果事务中涉及多个行锁，要把最可能造成锁冲突、最可能影响并发度的锁尽量往后放。

在读已提交隔离级别下有一个优化，即：语句执行过程中加上的行锁，在语句执行完成后，就要把“不满足条件的行”上的行锁直接释放了，不需要等到事务提交。也就是说，读提交隔离级别下，锁的范围更小，锁的时间更短，这也是不少业务都默认使用读提交隔离级别的原因。

> 死锁检测

- 直接进入等待，直到超时，可以通过参数 innodb_lock_wait_timeout 来设置，默认50s
- 发起死锁检测，发现死锁后，主动回滚死锁链条中的某一个事务，让其他事务得以继续执行。将参数 innodb_deadlock_detect 设置为 on，表示开启这个逻辑

由于第一种策略，时间无法预知，太短可能误伤。正常情况下采用第二种策略，即主动死锁检测，但又会消耗CPU资源。对于热点行的更新可能导致性能问题，解决思路：

- 对于不会出现死锁的业务，可以关掉死锁检测，存在风险
- 控制并发度
  - 客户端并发控制，但需要考虑分布式问题
  - 数据库端并发控制：数据库中间件实现或者修改Mysql源码(大神玩家)
- 业务设计上拆分，单行数据拆分为多行，减小并发度，例如：1一个账户拆分为多个子账户

> 思考题

如果删除一个表里面的前 10000 行数据，有以下三种方法可以做到：

- 第一种，直接执行 delete from T limit 10000;
- 第二种，在一个连接中循环执行 20 次 delete from T limit 500;
- 第三种，在 20 个连接中同时执行 delete from T limit 500。

哪一种方法更好？为什么？

**长事务、锁冲突**

## next-key lock

next-key lock由间隙锁(Gap Lock)和行锁组成，每个 next-key lock 是前开后闭区间，解决了幻读的问题。锁类型记为：LOCK_ORDINARY

间隙锁之间不存在冲突关系，**跟间隙锁存在冲突关系的，是“往这个间隙中插入一个记录”这个操作。**

> 举例说明

```mysql
CREATE TABLE `t` (
`id` int(11) NOT NULL,
`c` int(11) DEFAULT NULL,
`d` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `c` (`c`)
) ENGINE=InnoDB;

insert into t values(0,0,0),(5,5,5),
(10,10,10),(15,15,15),(20,20,20),(25,25,25);
```

| session A                              | session B                              |
| -------------------------------------- | -------------------------------------- |
| begin;                                 |                                        |
| select * from t where id=9 for update; |                                        |
|                                        | begin;                                 |
|                                        | select * from t where id=9 for update; |
|                                        | insert into t values(9,9,9);           |
| insert into t values(9,9,9);           |                                        |

上述语句执行结果如何？出现了死锁，为什么呢？

session A、session B中`select for update`由于id=9不存在，均加上了(5,10)的间隙锁，这也证明了间隙锁之间不存在冲突。接下来A、B都向这个间隙里插入数据，互相和对方持有的间隙锁冲突，相互等待形成死锁。如果开启了死锁检测，InnoDB会马上发现死锁关系，让A中插入报错返回。

从以上例子也可以看出，由于间隙锁的引入，虽然解决了幻读，可也影响了数据库的并发度。如果实际业务场景不需要保证可重复读，就可以考虑使用读已提交，同时binlog_format=row，保证主从同步的一致性。

> 加锁规则：两个原则、两个优化、一个bug

- 原则 1：加锁的基本单位是 next-key lock，前开后闭区间
- 原则 2：查找过程中访问到的对象才会加锁
- 优化 1：索引上的等值查询，给唯一索引加锁的时候，匹配上数据，next-key lock 退化为行锁
- 优化 2：索引上的等值查询，向右遍历时且最后一个值不满足等值条件的时候，next-key lock 退化为间隙锁
- 一个 bug：唯一索引上的范围查询会访问到不满足条件的第一个值为止

**以上规则，其实可以理解为数据查找过程中，扫描到的对象应该加锁，排除逻辑上明显不需要加锁的对象，即为加锁范围**

**重点：**

- **加锁是分步进行的，例如：`c>=10 and c<=11`，分解为c=10、c>10 and c<11、c=11依次进行锁申请**
- **间隙由右边的间隙记录，这也导致了不同方向上扫描加锁范围不一样**
- **从扫描到的第一个记录上作为起点，例如：普通索引c取值为[0,5,10,15,20]，c>10和c>=10其分别第一个扫描到的数为15、10，因此第一个间隙锁为(10,15]、(5,10]**

> 读已提交下的应用

在外键场景下有间隙锁，场景待确认

## insert intention lock

插入意向锁，仅用于insert语句，表明将在某间隙插入记录，与间隙锁互斥关系如下：

|                      | X,GAP | S,GAP | intention-insert   |
| -------------------- | ----- | ----- | ------------------ |
| **X,GAP**            | 兼容  | 兼容  | 互斥               |
| **S,GAP**            | 兼容  | 兼容  | 互斥               |
| **intention-insert** | 兼容  | 兼容  | 唯一键冲突可能互斥 |

- 间隙锁之间不存在互斥关系（X、S表示是什么语句导致的间隙锁）

- 间隙锁可以堵塞区间内的插入意向锁，但插入意向锁不会堵塞后续的间隙锁
- 唯一键冲突，如果是主键加记录锁，如果是唯一索引加next-key lock

> 插入意向锁实验验证

```mysql
mysql> CREATE TABLE `t` (
`id` int(11) NOT NULL,
`c` int(11) DEFAULT NULL,
`d` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `c` (`c`)
) ENGINE=InnoDB;

mysql> insert into t values(0,0,0),(5,5,5),
(10,10,10),(15,15,15),(20,20,20),(25,25,25);

-- 开启事务A
mysql> begin;

/**
在事务A中执行修改语句，id=7不存在，添加(5,10)的间隙锁，LOCK_MODE=X,GAP LOCK_DATA=10可以验证两个观点：
1、间隙锁是加在右边间隙上的
2、此处X并不代表10上加行锁，仅代表什么语句造成的，若改为select * from t where id=7 lock in share mode，LOCK_MODE就变为S,GAP
**/
mysql> update t set d=d+1 where id=7;

-- 在事务B中插入id=6的数据，需要申请插入意向锁，进入堵塞状态
mysql> insert into t values(6,6,6);

/**
事务A中已经添加了间隙锁，相同间隙的插入意向锁堵塞，LOCK_MODE=X,GAP,INSERT_INTENTION，LOCK_STATUS=WAITING
v8.0.11时，LOCK_MODE=X,GAP，INSERT_INTENTION标识是高版本新加的(此处使用的是8.0.21)，插入意向锁是一种特殊的间隙锁
**/
mysql> select THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+-----------+---------------+-------------+------------+-----------+------------------------+-------------+-----------+
| THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE              | LOCK_STATUS | LOCK_DATA |
+-----------+---------------+-------------+------------+-----------+------------------------+-------------+-----------+
|        54 | demo          | t           | NULL       | TABLE     | IX                     | GRANTED     | NULL      |
|        54 | demo          | t           | PRIMARY    | RECORD    | X,GAP                  | GRANTED     | 10        |
|        53 | demo          | t           | NULL       | TABLE     | IX                     | GRANTED     | NULL      |
|        53 | demo          | t           | PRIMARY    | RECORD    | X,GAP,INSERT_INTENTION | WAITING     | 10        |
+-----------+---------------+-------------+------------+-----------+------------------------+-------------+-----------+

-- 开启事务C
mysql> begin;

-- 在事务C中插入id=16的数据，由于该间隙上没有间隙锁，申请插入意向锁成功
mysql> insert into t values(16,16,16);

/** 
查询当前加锁情况，并没有发现插入意向锁，为什么？
插入意向锁是为了配合间隙锁解决幻读问题，在有间隙锁的情况下进行堵塞。此时没有间隙锁，不需要堵塞，所以就不用加插入意向锁吗？
但其他事务中相同行插入会产生冲突，说明这里还是有其他约束的，只是不用堵塞的插入意向锁转换成另外一种约束了
**/
mysql> select THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
|        53 | demo          | t           | NULL       | TABLE     | IX        | GRANTED     | NULL      |
+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
/**
证明其他约束的存在，新启一个事务，同样执行insert into t values(16,16,16)，可以看到申请S锁堵塞，正常上一个事务中的插入有其他约束
这里需要进行唯一约束验证，获取id=16的读锁
**/
mysql> select THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+-----------+---------------+-------------+------------+-----------+---------------+-------------+-----------+
| THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE     | LOCK_STATUS | LOCK_DATA |
+-----------+---------------+-------------+------------+-----------+---------------+-------------+-----------+
|        53 | demo          | t           | NULL       | TABLE     | IX            | GRANTED     | NULL      |
|        56 | demo          | t           | NULL       | TABLE     | IX            | GRANTED     | NULL      |
|        56 | demo          | t           | PRIMARY    | RECORD    | X,REC_NOT_GAP | GRANTED     | 16        |
|        56 | demo          | t           | PRIMARY    | RECORD    | S,REC_NOT_GAP | WAITING     | 16        |
+-----------+---------------+-------------+------------+-----------+---------------+-------------+-----------+


-- 开启事务D
mysql> begin;

-- 在事务D中插入id=10，
mysql> insert into t values(10,10,10);
1062 - Duplicate entry '10' for key 'PRIMARY'

-- 在事务E中插入id=9
mysql> insert into t values(9,9,9); 
(blocked)

/**V8.0.11
查看当前加锁情况，事务D插入语句检测到唯一冲突后在id=10上加了一个S锁
事务E中插入id=9，等待插入意向锁，没有间隙锁冲突，为什么会堵塞呢？
唯一键冲突加的应该不是一个记录S锁，应该是一个next-key lock (5,10]，因为已经存在间隙锁，所以插入意向锁才会堵塞
这是MySQL的一个bug，在V8.0.16已经修复，事务E中插入不会堵塞（主键唯一冲突就是一个单纯的记录锁）
https://bugs.mysql.com/bug.php?id=93806
**/
mysql> select THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t           | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       109 | demo          | t           | PRIMARY    | RECORD    | S         | GRANTED     | 10        |
| INNODB |       108 | demo          | t           | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t           | PRIMARY    | RECORD    | X,GAP     | WAITING     | 10        |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
```

## 加锁检测

- 等MDL锁

  ```mysql
  -- 事务A
  lock table test_data write;
  
  -- 由于事务A加了表锁，事务B堵塞
  select * from test_data;
  ```

- 等flush

  ```mysql
  -- 关闭表t
  flush tables t with read lock; 
  -- 关闭所有打开的表
  flush tables with read lock;
  
  -- 事务A
  select sleep(1) from t;
  
  -- 事务B：事务A中表t已打开，需要等待其结束
  flush tables t;
  
  -- 事务C：等待事务B中flush结束
  select * from t where id=1;
  ```

- 等行锁

  ```mysql
  -- 事务C
  begin
  update t set a=1 where id=1;
  
  -- 由于事务C行锁未提交，事务D相同行被堵塞
  update t set a=1 where id=1;
  ```

- 锁及堵塞查询

  ```mysql
  -- 查看表阻塞的process id(MySQL启动时需要设置performance_schema=on，相比于设置为off会有10%左右的性能损失)
  select blocking_pid from sys.schema_table_lock_waits;
  
  -- 查看行锁等待情况
  select * from sys.innodb_lock_waits;
  
  -- MySQL5.7及之前查看事务锁情况
  select * from performance_schema.innodb_locks;
  -- MySQL8.0及之后查看事务锁情况
  select * from performance_schema.data_locks;
  -- 查看元数据加锁情况
  select * from performance_schema.metadata_locks;
  
  -- 查看当前进程及状态
  show processlist;
  
  -- 查看innodb引擎状态，可以获取一些关键信息点，例如：最近事务及加锁情况，对分析定位问题有帮助
  show engine innodb status;
  ```

# join

## Index Nested-Loop Join(NLJ)

从驱动表上逐行读取数据，在**被驱动表上通过索引匹配数据**，假设驱动表N表数据，被驱动表M条数据

| Index Nested-Loop Join                                       | Batched Key Access(BKA，NLJ算法的优化)                       |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| <img src="https://sheungxin.github.io/notpic/f790d3cdd2ff48f98eb574ef8fd1c238.jpeg" alt="img" style="zoom:50%;" /> | <img src="https://sheungxin.github.io/notpic/b1acc4be1bbb44c6b8efc1de37a96de0.png" alt="img" style="zoom:50%;" /> |

- NLJ算法，每条数据都需要被驱动表两个索引上走一遍，近似时间复杂度为：

$$
N + N*2*log_2M
$$
​		其中N对最终结果影响较大，所以，该算法建议小表作为驱动表

- 使用BKA优化后，使用批量数据在被驱动表上进行匹配，近似时间复杂度为：
  $$
  N + K*2*log_2M
  $$
  其中K为驱动表分段数，join buffer可能一次性放不下所有数据。如果使用 BKA 优化算的话，设置如下：

  ```mysql
  -- BKA 算法的优化要依赖于MRR(Multi-Range Read)，也需要开启
  -- MRR的本质是二级索引获取尽可能多的主键id，经过排序后，在主键索引上顺序查找数据，减少了随机磁盘IO和主键索引访问次数
  set optimizer_switch='mrr=on,mrr_cost_based=on,batched_key_access=on';
  ```

  <img src="https://sheungxin.github.io/notpic/99ed1c91bb354bbebb556b0542be12c7.jpeg" alt="img" style="zoom:50%;" />

  注意：上图中如果结果集需要对a进行排序，使用MRR优化，经过排序的主键回表后得到的结果需要进行二次排序，可能得不偿失

## Block Nested-Loop Join(BNL)

把驱动表中数据读入内存join_buffer中，再把被驱动表中每一行数据取出来与join_buffer中数据比对（即使被驱动表上有过滤条件）

<img src="https://sheungxin.github.io/notpic/5ae664a192fe48b79c6153e904c22325.jpeg" alt="img" style="zoom:50%;" />

- 总的数据扫描行数为：N+K*M，K为驱动表分段数量，因为join_buffer可能不足以一次放下驱动表数据
- 内存判断次数为：N * M
- 驱动表分段会导致被驱动表多次读取
- 优化方案
  - 在被驱动表上建索引，直接转成BKA算法。不适合建索引的表，可通过有索引的临时表来触发BKA算法，提升查询性能
  - 可通过应用端配合模拟hash join，即把数据缓存的应用端hash结构中

## 驱动表选择

从以上两种算法的影响因子来看N对性能影响较大，因此建议小表作为驱动表。更准确地说，**在决定哪个表做驱动表的时候，应该是两个表按照各自的条件过滤，过滤完成之后，计算参与 join 的各个字段的总数据量，数据量小的那个表，就是“小表”，应该作为驱动表。**

# 临时表

```mysql
create temporary table …
```

临时表特点：

- 只对创建它的session可见
- 临时表可以与普通表同名，且同名情况下默认访问的是临时表（table_def_key在“库名+表名”的基础上又加入了“server_id+thread_id”）
- show tables不显示临时表
- 不需要担心数据删除问题，自动回收
- 内存临时表的大小由tmp_table_size决定，默认16M，超过后使用磁盘临时表
- 建议使用binlog_format=row，临时表的操作不记录到 binlog 中
- 只能使用`alter table temp_t rename to temp_t2`，不能使用`rename table temp_t2 to temp_t3`（基于“库名+表名”查找表）

> 应用场景：分库分表系统的跨库查询，例如：将一个大表 ht，按照字段 f，拆分成 1024 个分表，然后分布到 32 个数据库实例上

```mysql
select v from ht where k >= M order by t_modified desc limit 100;
```

<img src="https://sheungxin.github.io/notpic/48b913b1ff974ccda93558bca221caf7.jpeg" alt="img" style="zoom:50%;" />

> 临时表当前线程可见，为什么写binlog

```mysql
create table t_normal(id int primary key, c int)engine=innodb;

create temporary table temp_t like t_normal;

insert into temp_t values(1,1);/

insert into t_normal select * from temp_t;
```

如果binlog_format=statment/mixed，binlog不记录临时表的操作，从库只记录以下语句

```mysql
create table t_normal(id int primary key, c int)engine=innodb;

insert into t_normal select * from temp_t;
```

上述两条语句回放， insert into t_normal 的时候，就会报错“表 temp_t 不存在”。因此，需要在binlog中记录临时表的操作，且最后还要写一条`drop temporary table`在从库上清除临时表。所以，建议binlog_format=row，因为insert时会记录操作的数据，临时表操作就不需要记录在binlog中

# 高可用

![img](https://sheungxin.github.io/notpic/424830-20190401131734391-693482420.png)



| 应用层解决方案：TDDL、 Sharding-Jdbc (常用shardding-jdbc)    | 代理层解决方案：mysql proxy、mycat、altas (常用mycat)        |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| ![img](https://sheungxin.github.io/notpic/424830-20190401141200513-1826979161.png) | ![img](https://sheungxin.github.io/notpic/424830-20190401141049304-836975367.png) |

参考：https://www.cnblogs.com/gavin5033/p/12618108.html



# 常用命令

## explain

https://mp.weixin.qq.com/s/E8wJQvldwEAzxK5mEuFhog

## show processlist

https://www.cnblogs.com/remember-forget/p/10400496.html

## alter table t engine = InnoDB

|                        MySQL 5.6之前                         |                      MySQL 5.6+(Online)                      |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
| <img src="https://sheungxin.github.io/notpic/eabc13746a38.png" alt="img" style="zoom:50%;" /> | <img src="https://sheungxin.github.io/notpic/fe20cd8a3b4e42cdb09dae8c03d112da.png" alt="img" style="zoom:50%;" /> |

- MySQL 5.6 版本之前，整个 DDL 过程中，数据表不能有更新
- MySQL 5.6 版本开启引入Online DDL，使用row log记录和重放操作，允许DDL过程中进行增删改操作
- 重建表过程中，每个数据页会预留1/16的空闲空间用于后续更新使用。因此，重建表后不是最紧凑的，有可能空间占用变大

## analyze table t 

对表的索引信息做重新统计，没有修改数据，这个过程中加了 MDL 读锁

## optimize table t

等于 recreate+analyze

# 案例分析

## 可见性分析

```mysql
CREATE TABLE `t` (
`id` int(11) NOT NULL,
`k` int(11) DEFAULT NULL,
PRIMARY KEY (`id`)
) ENGINE=InnoDB;

insert into t(id, k) values(1,1),(2,2);
```

![img](https://sheungxin.github.io/notpic/9fa3e4bf3b48454d846cd403d43d9b9a.png)

- A：1
- B：3

## 数据修改的诡异现象

```mysql
begin;

select * from t;
+--------+----+
| id | c |
+--------+----+
| 1  | 1 |
| 2  | 2 |
| 3  | 3 |
| 4  | 4 |
+--------+----+

update t set c=0 where id=c;

select * from t;
+--------+----+
| id | c |
+--------+----+
| 1  | 1 |
| 2  | 2 |
| 3  | 3 |
| 4  | 4 |
+--------+----+
```

上文中update无法修改的问题，为什么会产生这种情况？

- 场景1：update之前，另一个事务B中执行update t set c=c+1
  - update是当前读，可以读取最新的数据，id不等于c，更新失败
  - select是快照读，事务B是处于高水位之后红色部分，对于select的事务不可见
- 场景2：第一次select前启动事务B，update前事务B执行update t set c=c+1，且提交
  - update是当前读，可以读取最新的数据，id不等于c，更新失败
  - select是快照读，事务B对于当前事务是活跃的，处于黄色部分，不可见

## 索引场景分析

```mysql
CREATE TABLE `geek` (
`a` int(11) NOT NULL,
`b` int(11) NOT NULL,
`c` int(11) NOT NULL,
`d` int(11) NOT NULL,
PRIMARY KEY (`a`,`b`),
KEY `c` (`c`),
KEY `ca` (`c`,`a`),
KEY `cb` (`c`,`b`)
) ENGINE=InnoDB;

select * from geek where c=N order by a limit 1;
select * from geek where c=N order by b limit 1;
```

非主键索引的叶子节点上会挂着主键，因此：

- 索引c+主键索引，可以看做是c、a、b
- 索引ca+主键索引，可以看做是c、a、b，重叠部分合并

由上可以得出，索引c可以等价于ca，保留较小的索引，去除索引ca

## 重建索引

```mysql
-- 非主键索引重建
alter table T drop index k;
alter table T add index(k);

-- 主键索引重建方式1
alter table T drop primary key;
1075 - Incorrect table definition; there can be only one auto column and it must be defined as a key
alter table T add primary key(id);

-- 主键索引重建方式2
alter table T engine=InnoDB;
```

- 索引重建：碎片整理可通过索引重建进行
- 主键索引：
  - InnoDB必须有一个主键索引，未主动声明时，Mysql会默认给创建一列6字节的整数列
  - 自增只能定义在索引列上，因此直接删除自增列上索引异常：1075
  - 主键索引重建方式1中删除并重建的方式，其实相当于创建了两次索引，建议采用方式2

## 大批量删除数据

```mysql
-- 第一种，直接执行 
delete from T limit 10000;

-- 第二种，在一个连接中循环执行 20 次 
delete from T limit 500;

-- 第三种，在 20 个连接中同时执行 
delete from T limit 500
```

- 第一种：长事务，索引时间较长，且可能导致主从延迟
- 第三种：人为造成锁冲突

## IS NULL、IS NOT NULL是否走索引

```mysql
mysql> show index from t;
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| Table | Non_unique | Key_name | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment |
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| t     |          0 | PRIMARY  |            1 | id          | A         |       93536 | NULL     | NULL   |      | BTREE      |         |               |
| t     |          1 | a        |            1 | a           | A         |       93536 | NULL     | NULL   | YES  | BTREE      |         |               |
+-------+------------+----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+

mysql> explain select * from t where a is null;
+----+-------------+-------+------+---------------+-----+---------+-------+------+-----------------------+
| id | select_type | table | type | possible_keys | key | key_len | ref   | rows | Extra                 |
+----+-------------+-------+------+---------------+-----+---------+-------+------+-----------------------+
|  1 | SIMPLE      | t     | ref  | a             | a   | 5       | const |    1 | Using index condition |
+----+-------------+-------+------+---------------+-----+---------+-------+------+-----------------------+
1 row in set

mysql> explain select * from t where a is not null;
+----+-------------+-------+------+---------------+------+---------+------+-------+-------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows  | Extra       |
+----+-------------+-------+------+---------------+------+---------+------+-------+-------------+
|  1 | SIMPLE      | t     | ALL  | a             | NULL | NULL    | NULL | 93536 | Using where |
+----+-------------+-------+------+---------------+------+---------+------+-------+-------------+
1 row in set
```

`is null`使用了索引，`is not null`未使用索引。那么，是否可以得出结论：`is null`走索引，`is not null`不走索引呢？

![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly9tbWJpei5xcGljLmNuL21tYml6L1JMbWJXV2V3NTVHQk5GVWVOdlhhSDNKWWpaZEF2Z1Q1dmlhZlFZSHYyVnYydnhTR0RnUmh3TEJhdk1ldm1lbmIxM2lhUWR0TDFyV21rSmpOaWJqancwTTFBLzY0MD93eF9mbXQ9b3RoZXImdHA9d2VicCZ3eGZyb209NSZ3eF9sYXp5PTEmd3hfY289MQ?x-oss-process=image/format,png)

对于二级索引来说，索引列的值可能为`NULL`，对于索引列值为`NULL`的二级索引记录来说，它们被放在`B+`树的最左边。由此，可以看出SQL中的`NULL`值认为是列中最小的值。因此，`is null`使用了索引，`is not null`由于需要查询所有值，最终还需要回表到主键索引，因此，直接使用全部扫描。

上述现象的本质还是优化器对索引成本的估算，如果上述案例中`a is NULL`的数量达到一定的程度，回表成本增加，可能就会被优化器放弃，改走全部扫描。

**同理，`!=、not in`是否走索引，都是同样的原理**。

## select count()

在不同的 MySQL 引擎中，count(*) 有不同的实现方式。

- MyISAM 引擎：表的总行数存在磁盘上，没有where条件的情况下，会直接返回这个数，效率很高；
- InnoDB 引擎：由于MVCC，不同事务中返回多少行是不确定的，需要把数据一行一行地从引擎里面读出来，然后累积计数。因此，优化器会找到最小的索引树来遍历

不同count的用法对比：

- count(1)：InnoDB 引擎遍历整张表，但不取值。server 层对于返回的每一行，放一个数字“1”进去，判断是不可能为空的，按行累加
- count(*)：MySQL专门进行了优化，不取值，等价于count(1)，建议优先使用
- count(主键id)：InnoDB 引擎会遍历整张表，把每一行的 id 值都取出来，返回给 server 层。server 层拿到 id 后，判断是不可能为空的，就按行累加
- count(字段)：
  - 如果这个“字段”是定义为 not null 的话，一行行地从记录里面读出这个字段，判断不能为 null，按行累加；
  - 如果这个“字段”定义允许为 null，那么执行的时候，判断到有可能是 null，还要把值取出来再判断一下，不是 null 才累加

## order by工作方式

```mysql
CREATE TABLE `t` (
	`id` INT (11) NOT NULL,
	`city` VARCHAR (16) NOT NULL,
	`name` VARCHAR (16) NOT NULL,
	`age` INT (11) NOT NULL,
	`addr` VARCHAR (128) DEFAULT NULL,
	PRIMARY KEY (`id`),
	KEY `city` (`city`)
) ENGINE = INNODB;

select city,name,age from t where city='杭州' order by name limit 1000;

--  MySQL中用于控制排序行数据长度的一个参数，如果单行的长度超过这个值，改用rowid排序
SET max_length_for_sort_data = 16;
```

|                          全字段排序                          |                          rowid 排序                          |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
| <img src="https://sheungxin.github.io/notpic/8be2cd787b764d2e8f3c979d5dcfd4e3.jpeg" alt="img" style="zoom: 50%;" /> | <img src="https://sheungxin.github.io/notpic/7adf45aa02c44057a5a8646b3f39b9e9.jpeg" alt="img" style="zoom: 50%;" /> |

- sort_buffer_size：如果要排序的数据量小于 sort_buffer_size，排序就在内存中完成。反之，利用磁盘临时文件辅助排序
- rowid 排序多访问了一次表 t 的主键索引，因此，MySQL会优先选择全字段排序，可以通过修改参数`max_length_for_sort_data`让优化器选择rowid排序算法，默认16，当要查询的单条数据全文本长度大于16采用rowid排序
- 对于需要使用临时表进行排序时，需要看临时表是内存临时表，还是磁盘临时表，由tmp_table_size决定，默认16M。若是内存临时表，回表在内存中完成，不会访问磁盘，优先选用rowid排序

优化方案：使数据本身有序

```mysql
alter table t add index city_user(city, name);

-- 利用索引中相同city下name有序性
select city,name,age from t where city='杭州' order by name limit 1000;

-- 进一步优化，使用覆盖索引，减少回表
alter table t add index city_user_age(city, name, age);

-- city多值情况下，又该如何处理？ sql拆分
select * from t where city in ('杭州'," 苏州 ") order by name limit 100;
```

## group by优化

```mysql
CREATE TABLE t1 (
	id INT PRIMARY KEY,
	a INT,
	b INT,
	INDEX (a)
);

select id%10 as m,count(*) as c from t2 group by m;
```

首先分析下group by语句的执行计划，如下：

```mysql
-- 此处使用MySQL 8.0+，已取消group by隐式排序，否则Exta中还会多一个Using filesort
mysql> explain select id%10 as m,count(*) from t group by m;
+----+-------------+-------+------------+-------+---------------+-----+---------+------+--------+----------+------------------------------+
| id | select_type | table | partitions | type  | possible_keys | key | key_len | ref  | rows   | filtered | Extra                        |
+----+-------------+-------+------------+-------+---------------+-----+---------+------+--------+----------+------------------------------+
|  1 | SIMPLE      | t2    | NULL       | index | PRIMARY,a     | a   | 5       | NULL | 998529 |      100 | Using index; Using temporary |
+----+-------------+-------+------------+-------+---------------+-----+---------+------+--------+----------+------------------------------+
```

<img src="https://sheungxin.github.io/notpic/ce46acf39a8e4812abe3cad8e0ef84da.jpeg" alt="img" style="zoom:50%;" />

- 只用到了主键id字段，可以使用覆盖索引，因此选择了索引a，不用回表
- 获取主键id，id%10后放入临时表，如果存在，计数列加1

- MySQL 8.0前group by支持隐式排序，无排序需求时，建议加上order by null

> 如何优化？

- 适合创建索引，直接加索引

    ```mysql
    -- 此处举例中分组字段是不存在，新增一个，并创建索引
    -- 实际场景中可能会有已有分组字段，但未加索引，加上索引即可
    mysql> alter table t1 add column z int generated always as(id % 100), add index(z);
    
    -- 使用索引字段进行分组排序
    mysql> explain select z as m,count(*) from t1 group by z ;
    +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-------------+
    | id | select_type | table | partitions | type  | possible_keys | key | key_len | ref  | rows | filtered | Extra       |
    +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-------------+
    |  1 | SIMPLE      | t1    | NULL       | index | z             | z   | 5       | NULL | 1000 |      100 | Using index |
    +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-------------+
    ```

    - 索引是有序的，顺序扫描，依次累加，统计完一个再统计下一个，不需要暂存中间结果，也不需要额外排序。如果需要倒序排列，Backward index scan，从后扫描索引即可

    - 多个分组字段，建议使用联合索引

- 不适合创建索引，数据量不大，走内存临时表即可。如果数据量较大，使用SQL_BIG_RESULT告诉优化器，放弃内存临时表，直接磁盘临时表

  ```mysql
  mysql> explain select SQL_BIG_RESULT id%10 as m,count(*) from t1 group by m ;
  +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-----------------------------+
  | id | select_type | table | partitions | type  | possible_keys | key | key_len | ref  | rows | filtered | Extra                       |
  +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-----------------------------+
  |  1 | SIMPLE      | t1    | NULL       | index | PRIMARY,a,z   | a   | 5       | NULL | 1000 |      100 | Using index; Using filesort |
  +----+-------------+-------+------------+-------+---------------+-----+---------+------+------+----------+-----------------------------+
  ```
  
  通过执行计划可以看出实际并未使用临时表，为什么呢？
  
  因此，磁盘临时表是B+树存储，存储效率不高，从磁盘空间考虑，直接使用数组存储，流程如下：
  
  <img src="https://sheungxin.github.io/notpic/330a08b14a0242298706dba84746ceb3.jpeg" alt="img" style="zoom:50%;" />
  
  直接把分组值m放在sort_buffer中，空间不足使用磁盘临时文件辅助排序，这样就得到一个有序数组。在有序数组上计算相同值出现的次数就比较简单了，和在索引上统计计数一样，逐个累加计数即可。

## 慢查询分析

- 示例1：

| session A                                      | session B                                   |
| :--------------------------------------------- | :------------------------------------------ |
| start transaction with consistent snapshot；   |                                             |
|                                                | update t set c=c+1 where id=1;//执行100万次 |
| select * from t where id=1;                    |                                             |
| select * from t where id=1 lock in share mode; |                                             |

<img src="https://sheungxin.github.io/notpic/16c9ecc9bb0447f8aad7c804c2fe0fe9.png" alt="img" style="zoom:50%;" />

- 示例2：

```mysql
-- 创建表t
CREATE TABLE `t` (
	`id` INT (11) NOT NULL,
	`b` VARCHAR (10) NOT NULL,
	PRIMARY KEY (`id`),
	KEY `b` (`b`)
) ENGINE = INNODB;

-- 值超出字段长度，字符串截断后传递给执行引擎，可能匹配上大量数据，最终导致大量回表二次验证b='1234567890abcd'
explain select * from t where b='1234567890abcd';

-- 类型隐式转换，扫描全部索引树
explain select * from t where b=1235
```

## 互关问题设计

业务上有这样的需求，A、B 两个用户，如果互相关注，则成为好友。

```mysql
-- 创建关注表
CREATE TABLE `like` (
	`id` INT (11) NOT NULL AUTO_INCREMENT,
	`user_id` INT (11) NOT NULL,
	`liker_id` INT (11) NOT NULL,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uk_user_id_liker_id` (`user_id`, `liker_id`)
) ENGINE = INNODB;

-- 创建好友表
CREATE TABLE `friend` (
	`id` INT (11) NOT NULL AUTO_INCREMENT,
	`friend_1_id` INT (11) NOT NULL,
	`friend_2_id` INT (11) NOT NULL,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uk_friend` (
		`friend_1_id`,
		`friend_2_id`
	)
) ENGINE = INNODB;
```

| session1（A关注B，A=1，B=2）                                 | session2（B关注A，A=1，B=2）                                 |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| begin;                                                       |                                                              |
| select * from user_like where user_id=2 and liker_id=1;(Empty set) | begin;                                                       |
| insert into user_like(user_id,liker_id) values(1,2);         |                                                              |
|                                                              | select * from user_like where user_id=1 and liker_id=2;(Empty set) |
|                                                              | insert into user_like(user_id,liker_id) values(2,1);         |
| commit;                                                      |                                                              |
|                                                              | commit;                                                      |

A、B两个用户同时关注对方，即使session2中select先于session1中insert操作，session2也无法感知其未提交的数据。从而两个session执行完后建立了双向关注，但未建立好友关系。如何解决？

>  方案1：按照规则，使AB互关映射到同一条数据上，通过行锁冲突+on duplicate key实现好友关系的建立

```mysql
-- 增加互关关系字段
ALTER TABLE `user_like`
ADD COLUMN `relation_ship`  int NOT NULL AFTER `liker_id`;

-- 按照用户编号正序排列，不关A关注B，还是B关注A，都会命中同一条数据，用relation_ship标识两者之间的关系

-- A关注B，若A=1、B=2
insert into user_like(user_id,liker_id,relation_ship) values(1,2,1) on duplicate key update relation_ship = relation_ship|1;

-- A关注B，若A=2、B=1
insert into user_like(user_id,liker_id,relation_ship) values(1,2,2) on duplicate key update relation_ship = relation_ship|2;

-- 查询AB之前的关系
select relation_ship from user_like where user_id=1 and liker_id=2;

-- 以上两条insert执行后，上一步查询的relation_ship=1|2=3，可执行好友插入
insert ignore into user_friend(friend_1_id, friend_2_id) values(1,2);
```

- on duplicate key需要建立在主键或者唯一键的基础上
- insert ignore可保证好友插入的幂等性
- 好处在于两条数据记录了关注和好友关系
- 坏处在于不便于查询场景实现（可在异构数据源上进行查询）
  - 查询场景复杂化，例如：查询用户A关注的用户，`(user_id=A and relation_ship<>2) or (liker_id=A and relation_ship=3)`
  - 现有索引无法满足查询场景
  - 分表的情况下，无法映射指定用户到单一的表上，例如：查询用户A关注的用户

> 方案2：新的事务中或者异步调用好友关系建立服务

```mysql
begin;

-- 验证双向关系是否存在，即存在两条数据
select couny(*) from user_like where user_id in (1,2) and liker_id in (1,2);

-- 双向关系存在，插入两条双向好友关系
insert ignore into user_friend (friend_1_id,friend_2_id)  select 
user_id,liker_id from user_like where user_id in (1,2) and liker_id in (1,2);
```

- 好处在于关注和好友关系明确，查询实现简单
- 坏处在于数据存储量翻倍，且关注和友好的建立不在同一个事务中，好友的建立有可能失败，需要提供补偿机制

## 更新中当前读问题

```mysql
CREATE TABLE `t` (
	`id` INT (11) NOT NULL,
	`a` INT (11) NOT NULL,
	PRIMARY KEY (`id`)
) ENGINE = INNODB;

insert into t values(1,2);
```

| session A                    | session B                    |
| ---------------------------- | ---------------------------- |
| begin;                       |                              |
| select * from t where id=1;  |                              |
|                              | update t set a=3 where id=1; |
| update t set a=3 where id=1; |                              |
| select * from t where id=1;  |                              |
| update t set a=4 where id=1; |                              |
| select * from t where id=1;  |                              |

session A中后两次select返回结果是什么？

有疑问的在于第二次，由于session B中已经把a修改为了3，session A中update是当前读，就看是否可以感知a已变更为3。MySQL 8.0.11中已感知不会执行修改操作，第二次读取的快照读还是(1,2)。有说法是update中当前读读取的只是where条件中的列，无法感知a是否变更，执行了修改操作，第二次读取结果为(1,3)

## 随机显示N条数据

- 方案1：随机函数排序

  ```mysql
  -- 不建议采用：排序耗费资源
  select * from t order by rand() limit n;
  ```

- 方案2：随机主键

  ```mysql
  -- 查询主键取值区间
  select max(id),min(id) into @M,@N from t ;
  
  -- 随机一个主键区间的值
  set @X=floor((@M-@N+1)*rand() + @N);
  
  -- 随机的主键值可能不存在，使用范围查找
  select * from t where id >= @X limit 1;
  ```

  缺点：

  - 只适用取一条数据，多条数据返回查找可能不够
  - 主键分布不均衡的情况下，不同行概率不一样，例如：1、2、3、40000、400001

- 方案3：随机行数

  ```mysql
  -- 获取总行数
  select count(*) into @C from t;
  
  -- 设置随机显示数量
  set @N = 1;
  
  -- 计算起始行数
  set @Y = floor(@C * rand())-@N+1;
  
  -- 拼接sql
  set @sql = concat("select * from t limit ", @Y, ",", @N);
  
  -- 预处理语句
  prepare stmt from @sql;
  
  -- 执行语句
  execute stmt;
  
  -- prepare、execute、deallocate统称为prepare statement，称为预处理语句，deallocate用于释放资源
  deallocate prepare stmt;
  ```

## 间隙锁加锁分析

以下案例均基于以下表及数据

```mysql
CREATE TABLE `t` (
`id` int(11) NOT NULL,
`c` int(11) DEFAULT NULL,
`d` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `c` (`c`)
) ENGINE=InnoDB;

insert into t values(0,0,0),(5,5,5),
(10,10,10),(15,15,15),(20,20,20),(25,25,25);
```

### 案例一：等值查询间隙锁

| session A                      | session B                    | session C                       |
| ------------------------------ | ---------------------------- | ------------------------------- |
| begin;                         |                              |                                 |
| update t set d=d+1 where id=7; |                              |                                 |
|                                | insert into t values(8,8,8); |                                 |
|                                |                              | update t set d=d+1 where id=10; |

加锁范围(5,10)，B被堵塞，C正常执行

### 案例二：非唯一索引等值锁

| session A                                      | session B                      | session C                    |
| :--------------------------------------------- | ------------------------------ | ---------------------------- |
| begin;                                         |                                |                              |
| select id from t where c=5 lock in share mode; |                                |                              |
|                                                | update t set d=d+1 where id=5; |                              |
|                                                |                                | insert into t values(7,7,7); |

- 加锁范围：(0,10)，C被堵塞
- 查找c=5仅需要返回id，id作为主键索引，在二级索引上有，走覆盖索引即可。因此，主键索引没有被访问，不用加锁，B正常执行

### 案例三：主键索引范围锁

| session A                                          | session B                       | session C                       |
| -------------------------------------------------- | ------------------------------- | ------------------------------- |
| begin;                                             |                                 |                                 |
| select * from t where id>=10 and id<11 for update; |                                 |                                 |
|                                                    | insert into t values(8,8,8);    |                                 |
|                                                    | insert into t values(13,13,13); |                                 |
|                                                    |                                 | update t set d=d+1 where id=15; |

加锁范围[10,15]：

- B中第一次插入成功，第二次插入堵塞
- C中更新堵塞

**把 A中`id>=10 and id<11`改为`id>=10 and id<=11`，C不再堵塞，为什么？**

锁是一个一个申请的，要分开来看。`id>=10 and id<=11`可分解为

- `id=10`：加锁范围行锁(10)，主键且数据存在，退化为行锁，去除间隙锁(5,10)
- `id>10 and id<11`：第一个扫描到的数是15，默认加锁范围(10,15]
- `id=11`：第一个扫描到的数也是15，由于是主键退化为间隙锁(10,15)，(15)上不再加锁

### 案例四：非唯一索引范围锁

| session A                                        | session B                    | session C                      |
| ------------------------------------------------ | ---------------------------- | ------------------------------ |
| begin;                                           |                              |                                |
| select * from t where c>=10 and c<11 for update; |                              |                                |
|                                                  | insert into t values(8,8,8); |                                |
|                                                  |                              | update t set d=d+1 where c=15; |

加锁范围(5,15]，B、C均堵塞

**把 A中`c>=10 and c<11`改为c>=10 and c<=11`，C依然堵塞，对比案例三**

锁是一个一个申请的，要分开来看。`id>=10 and id<=11`可分解为

- `c=10`：加锁范围行锁(5,10]
- `c>10 and c<11`：第一个扫描到的数是15，默认加锁范围(10,15]
- `c=11`：第一个扫描到的数也是15，加锁范围(10,15]，(15)上仍然有锁

**把 A中`c>=10 and c<11`改为c>10 and c<11`，锁范围如何变化**

首个扫描到的数据为c=15，加锁范围(10,15]

### 案例五：唯一索引范围锁 bug

| session A                                          | session B                       | session C                       |
| -------------------------------------------------- | ------------------------------- | ------------------------------- |
| begin;                                             |                                 |                                 |
| select * from t where id>10 and id<=15 for update; |                                 |                                 |
|                                                    | insert into t values(16,16,16); |                                 |
|                                                    |                                 | update t set d=d+1 where id=20; |

加锁范围(10,20]，B、C均堵塞

### 案例六：limit 语句加锁

```mysql
insert into t values(30,10,30);
insert into t values(40,10,40);
```

| session A                         | session B                       | session C                       |
| --------------------------------- | ------------------------------- | ------------------------------- |
| begin;                            |                                 |                                 |
| delete from t where c=10 limit 2; |                                 |                                 |
|                                   | insert into t values(12,12,12); |                                 |
|                                   |                                 | update t set d=d+1 where id=40; |
|                                   |                                 | update t set d=d+1 where id=30; |

- 加上limit 2，加锁范围由(5,15)退化为(5,10]，B中插入不再堵塞
- limit N决定了右区间的边界，C中第一次正常执行，第二次更新堵塞

### 案例七：死锁

| session A                                       | session B                      |
| ----------------------------------------------- | ------------------------------ |
| begin;                                          |                                |
| select id from t where c=10 lock in share mode; |                                |
|                                                 | update t set d=d+1 where c=10; |
| insert into t values(8,8,8);                    |                                |

A中`lock in share mode`加锁范围(5,15)，B先堵塞，在A中执行插入后检测到死锁异常。原因在于间隙锁和行锁是分开申请的，间隙锁之间不冲突。B先申请到(5,10)的间隙锁，再申请c=10的行锁，由于行锁已被A获取而堵塞。接下来，A执行插入，和B中间隙锁冲突，形成循环等待。

### 案例八：数据删除，锁范围扩大

| session A                                      | session B                       | session C                       |
| :--------------------------------------------- | ------------------------------- | ------------------------------- |
| begin;                                         |                                 |                                 |
| select id from t where c=5 lock in share mode; |                                 |                                 |
|                                                | insert into t values(13,13,13); |                                 |
|                                                | delete from t where c=10;       |                                 |
|                                                |                                 | insert into t values(12,12,12); |

A中`lock in share mode`加锁范围(0,10)，B中插入数据`c=13`成功，C中插入数据`c=12`堵塞，均值间隙锁之外为什么后者会堵塞？

B中删除破坏了原有间隙锁结构，间隙锁扩大到(0,13)

### 案例九：排序对加锁的影响

| session A                                                    | session B                    |
| :----------------------------------------------------------- | ---------------------------- |
| begin;                                                       |                              |
| select * from t where c>=15 and c<=20 order by c desc lock in share mode; |                              |
|                                                              | insert into t values(6,6,6); |

先不关心排序带来的影响，A中范围查询正常加锁范围为(10,25]，B中c=6插入是不会堵塞的。倒序排列后，如果还是从左边开始查找，最终结果是倒序的，还需要把结果集倒置。因此，从右边开始查找，即20开始找，加锁规则不变，还是左开右闭，一直查找到10为止，加锁是以next-key lock为单位，所以会加到(5,10]上，导致B中插入语句堵塞。

### 案例十：加锁顺序带来的死锁

| session A                                                | session B                                                    |
| :------------------------------------------------------- | ------------------------------------------------------------ |
| begin;                                                   |                                                              |
| select id from t where c in(5,20,10) lock in share mode; |                                                              |
|                                                          | select id from t where c in(5,20,10) order by c desc for update; |

A、B都需要在c=5、c=10、c=20上加锁，由于B中使用了倒序导致查找顺序相反，加锁顺序也刚好相反，一定并发下就会存在相互等待从而死锁。例如：

- A先在c=5上成功加锁
- B在c=20、c=10上依次成功加锁
- A在c=10上加锁时，需要等待B中c=10上的行锁释放
- B在c=5上加锁时，同样需要等待A中c=5上的行锁释放

### insert加锁分析

| session A                    | session B                    | session C                    |
| :--------------------------- | ---------------------------- | ---------------------------- |
| begin;                       |                              |                              |
| insert into t values(6,6,6); |                              |                              |
|                              | insert into t values(7,7,7); |                              |
|                              |                              | insert into t values(4,4,4); |

```mysql
-- A中插入语句执行后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t           | NULL       | TABLE     | IX        | GRANTED     | NULL      |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
```

A中只有一个表级锁IX(排他意向锁)，对B、C的插入语句没有影响，B、C正常执行。A、B、C均申请各自的插入意向锁，分属不同的行，不存在冲突

### insert唯一键冲突堵塞

```mysql
-- 把字段c上索引改为唯一索引
ALTER TABLE `t`
DROP INDEX `c` ,
ADD UNIQUE INDEX `c` (`c`) USING BTREE ;
```

| session A                               | session B                                                    |
| :-------------------------------------- | ------------------------------------------------------------ |
| begin;                                  |                                                              |
| insert into t values(11,10,10);         |                                                              |
| 1062 - Duplicate entry '10' for key 'c' | insert into t values(9,9,9);                                 |
|                                         | 1205 - Lock wait timeout exceeded; try restarting transaction |

```mysql
-- A中执行insert后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       109 | demo          | t3          | c          | RECORD    | S         | GRANTED     | 10        |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+

-- B中执行insert后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       109 | demo          | t3          | c          | RECORD    | S         | GRANTED     | 10        |
| INNODB |       108 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X,GAP     | WAITING     | 10        |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
```

根据上述加锁情况可发现，唯一键冲突的时候，在冲突的索引c=10上加了一个读锁。B中执行insert语句需要在c=10上加一个next-key lock，需要获取c=10的X锁，与A中c=10的S冲突，造成B堵塞。

根据官方唯一冲突加锁规则，非主键唯一冲突应该加的是间隙锁，B中插入时申请插入意向锁与间隙锁是同一间隙范围，被堵塞了，也解释的通，但和上述加锁对不上

### insert唯一键冲突死锁

| session A                    | session B                    | session C                    |
| ---------------------------- | ---------------------------- | ---------------------------- |
| begin;                       |                              |                              |
| insert into t values(6,6,6); |                              |                              |
|                              | insert into t values(7,6,6); |                              |
|                              |                              | insert into t values(8,6,6); |
| rollback;                    |                              |                              |

rollback后，B、C死锁，如开启死锁检测，其中一个事务异常返回，为什么？

```mysql
-- A中执行insert后加锁情况，只看了一个表级IX
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
1 row in set

/**
B中执行insert后加锁情况，申请到了c=6的写锁，等待c=6的读锁，为什么？
此时c=6不存在，X锁加锁成功，但由于c是唯一索引，需要去验证唯一性，A中插入未提交，等待读锁
**/
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | GRANTED     | 6         |
| INNODB |       108 | demo          | t3          | c          | RECORD    | S         | WAITING     | 6         |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
4 rows in set

/** 
C中执行insert后加锁情况，等待c=6的读锁
**/
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | GRANTED     | 6         |
| INNODB |       108 | demo          | t3          | c          | RECORD    | S         | WAITING     | 6         |
| INNODB |       114 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       114 | demo          | t3          | c          | RECORD    | S         | WAITING     | 6         |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
```

A回滚后，B、C都成功获取S锁，执行插入需要相互等待对方的S锁，进行死锁，是否可优化？

| session A                    | session B                                                | session C                                                |
| ---------------------------- | -------------------------------------------------------- | -------------------------------------------------------- |
| begin;                       |                                                          |                                                          |
| insert into t values(6,6,6); |                                                          |                                                          |
|                              | insert into t values(7,6,6) on duplicate key update d=7; |                                                          |
|                              | Query OK, 1 rows affected                                | insert into t values(7,6,6) on duplicate key update d=8; |
| rollback;                    |                                                          | Query OK, 2 rows affected                                |

```mysql
-- A中执行insert后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+

-- B中执行insert后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | GRANTED     | 6         |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | WAITING     | 6         |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+

-- C中执行insert后加锁情况
mysql> select ENGINE,THREAD_ID,OBJECT_SCHEMA,OBJECT_NAME,INDEX_NAME,LOCK_TYPE,LOCK_MODE,LOCK_STATUS,LOCK_DATA 
from performance_schema.data_locks;
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| ENGINE | THREAD_ID | OBJECT_SCHEMA | OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS | LOCK_DATA |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
| INNODB |       109 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | GRANTED     | 6         |
| INNODB |       108 | demo          | t3          | c          | RECORD    | X         | WAITING     | 6         |
| INNODB |       114 | demo          | t3          | NULL       | TABLE     | IX        | GRANTED     | NULL      |
| INNODB |       114 | demo          | t3          | PRIMARY    | RECORD    | X         | WAITING     | 7         |
| INNODB |       114 | demo          | t3          | PRIMARY    | RECORD    | X         | WAITING     | 7         |
+--------+-----------+---------------+-------------+------------+-----------+-----------+-------------+-----------+
```

**insert into … on duplicate key update**会给索引 c 上 (5,10] 加一个排他的 **next-key lock（写锁）**，所以A回滚前B、C不会持有锁。回滚后，先抢到写锁的执行插入，提交后另一个事务执行更新

## join优化

```mysql
CREATE TABLE `t1` (
`id` int(11) NOT NULL,
`a` int(11) DEFAULT NULL,
`b` int(11) DEFAULT NULL,
`c` int(11) DEFAULT NULL,
PRIMARY KEY (`id`)
) ENGINE=InnoDB;

create table t2 like t1;
create table t3 like t2;
--  初始化三张表的数据
insert into ... 

-- 以下查询需要加哪些索引来优化？
SELECT
	*
FROM
	t1
JOIN t2 ON (t1.a = t2.a)
JOIN t3 ON (t2.b = t3.b)
WHERE
	t1.c >= X
AND t2.c >= Y
AND t3.c >= Z;
```

索引原则，尽量使用BKA算法，小表作为驱动表，假设第一个驱动表为：

- t1：连接顺序为t1->t2->t3，要在被驱动表字段创建上索引，也就是 t2.a 和 t3.b 上创建索引
- t2：连接顺序不确定，需要评估另外两个条件的过滤效果，都需要在t1.a、t3.b上创建索引
- t3：连接顺序是 t3->t2->t1，需要在 t2.b 和 t1.a 上创建索引

同时，还需要在第一个驱动表的字段 c 上创建索引

## 自增主键是否连续

自增主键可能不连续，可能原因如下：

- 自增值保存策略
  - 在 MySQL 5.7 及之前的版本，自增值保存在内存里，并没有持久化。每次重启后，第一次打开表的时候，都会去找自增值的最大值 max(id)，然后将 max(id)+1 作为这个表当前的自增值
  - 在 MySQL 8.0 版本，将自增值的变更记录在了 redo log 中，重启的时候依靠 redo log 恢复重启之前的值
- 自增值修改机制
  - 如果插入数据时 id 字段指定为 0、null 或未指定值，那么就把这个表当前的 AUTO_INCREMENT 值填到自增字段
  - 指定插入的主键值时，根据自增值生成算法计算新的自增值，影响参数： auto_increment_offset 、auto_increment_increment 
- 自增值申请后未使用不允许回退
- 同一个语句多次申请自增id，每一次申请是前一次的两倍，可能造成浪费

MySQL 5.1.22 版本开始引入的参数 innodb_autoinc_lock_mode（默认1，语句结束后释放自增锁），控制了自增值申请时的锁范围。

默认值是 1。

- 0 ：表示采用之前 MySQL 5.0 版本的策略，即语句执行结束后才释放锁
- 1 ：普通 insert 语句，自增锁在申请之后就马上释放；**类似 insert … select 这样的批量插入数据的语句，自增锁还是要等语句结束后才被释放**。不包括普通的insert语句中包含多个value值的批量插入，因为可以计算需要多少个id，一次性申请后即可释放
- 2：申请后就释放锁（8.0默认值已改为2）

从并发性能的角度考虑，建议将其设置为 2，同时将 binlog_format 设置为 row

## 误删数据解决方案

误删数据分类：

- 使用 delete 语句误删数据行
  - 确保 binlog_format=row 和 binlog_row_image=FULL的前提下，使用Flashback工具闪回恢复数据
  - 建议在从库上执行，避免对数据的二次破坏(数据变更是有关联的，有可能因为误操作的数据触发其他业务逻辑，从而导致其他数据的变更。因此，数据恢复需要再从库上进行，验证后再恢复回主库)
  - 事前预防， `sql_safe_updates=on`关闭批量修改或删除，增加SQL审计
- 误删库/表：drop table 、truncate table、drop database
  - 恢复方案：全量备份+实时备份binlog，可通过延迟复制备库优化，相当于一个最近可用的全量备份
  - 预防方案：权限控制、制定操作规范(例如：先备份后删除，只能删除指定后缀表)
- rm删除数据：高可用集群即可，HA机制会重新选择一个主库

## insert ...select加锁分析

```mysql
CREATE TABLE `t` (
`id` int(11) NOT NULL AUTO_INCREMENT,
`c` int(11) DEFAULT NULL,
`d` int(11) DEFAULT NULL,
PRIMARY KEY (`id`),
UNIQUE KEY `c` (`c`)
) ENGINE=InnoDB;

insert into t values(null, 1,1);
insert into t values(null, 2,2);
insert into t values(null, 3,3);
insert into t values(null, 4,4);

create table t2 like t

-- 语句1：不走索引，加锁范围：所有行锁和间隙锁
mysql> explain insert into t2(c,d) select c,d from t;
+----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------+
| id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra |
+----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------+
|  1 | INSERT      | t3    | NULL       | ALL  | NULL          | NULL | NULL    | NULL | NULL | NULL     | NULL  |
|  1 | SIMPLE      | t     | NULL       | ALL  | NULL          | NULL | NULL    | NULL |    4 |      100 | NULL  |
+----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------+

-- 语句2：强制走索引c，倒序取第一条，加锁范围：(3,4]、(4,supremum] 
mysql> explain insert into t2(c,d) (select c+1, d from t force index(c) order by c desc limit 1);
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+---------------------+
| id | select_type | table | partitions | type  | possible_keys | key  | key_len | ref  | rows | filtered | Extra               |
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+---------------------+
|  1 | INSERT      | t2    | NULL       | ALL   | NULL          | NULL | NULL    | NULL | NULL | NULL     | NULL                |
|  1 | SIMPLE      | t     | NULL       | index | NULL          | c    | 5       | NULL |    1 |      100 | Backward index scan |
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+---------------------+

-- 语句3：从表t查询数据，再插入到自身，需要暂存中间数据，使用了临时表，在临时表上limit，
-- 加锁范围：所有行锁和间隙锁(8.0.11上和语句2一样，锁范围未发生变化)
mysql> explain insert into t(c,d) (select c+1, d from t force index(c) order by c desc limit 1);
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+--------------------------------------+
| id | select_type | table | partitions | type  | possible_keys | key  | key_len | ref  | rows | filtered | Extra                                |
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+--------------------------------------+
|  1 | INSERT      | t     | NULL       | ALL   | NULL          | NULL | NULL    | NULL | NULL | NULL     | NULL                                 |
|  1 | SIMPLE      | t     | NULL       | index | NULL          | c    | 5       | NULL |    1 |      100 | Backward index scan; Using temporary |
+----+-------------+-------+------------+-------+---------------+------+---------+------+------+----------+--------------------------------------+

-- 假设语句3，先把数据放入临时表，再进行limit，会扫描所有行，如何优化？
create temporary table temp_t(c int,d int) engine=memory;
insert into temp_t (select c+1, d from t force index(c) order by c desc limit 1);
insert into t select * from temp_t;
drop table temp_t;
```

