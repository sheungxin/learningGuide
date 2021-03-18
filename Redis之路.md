[toc]

# 特性

- 高性能
  - opoll模型：基于非阻塞的IO多路复用机制
  - k-v结构，v支持多种数据类型，进行了大量优化，性能极高
  - 基于内存操作
  - 单线程（命令执行线程），无上下文切换成本
  - 分片存储
- 数据结构丰富
- 高可用
- 原子性
- 可持久化
- 易于扩展

# 整体结构

## redisServer

Redis作为一个NoSQL数据库，其底层数据结构是如何构建的？我们可以从redisServer入手，配置如下：

```c
struct redisServer {
    ...
    dict *pubsub_channels; // 用于保存订阅频道的信息，精确匹配
    list *pubsub_patterns; // 链表中保存着所有和订阅模式相关的信息，模糊匹配
    redisDb *db;	// *db就是存储键值对的地方，本质上一个数组
    int dbnum;	   // 配置的数据库实例数量，默认支持16个数据库，默认选中0号数据库
};
```

- Redis不支持自定义数据库的名字，每个数据库都以编号命名
- Redis不支持为每个数据库设置不同的访问密码
- FLUSHALL会清空实例下所有数据库数据，db应该理解为“命名空间”，不适用于使用多个数据库实例存储不同应用的数据，可以用于存储相同应用不同环境的数据
- Redis非常轻量，一个空的数据库实例内存占用只有1M作用
- 集群模式不支持select命令切换db，只有一个db0

## redisDb

上文介绍了redisDB的概念，接下来看一下redisDb的具体结构，如下所示：

```c
typedef struct redisDb {
    dict *dict;             // 当前数据库的键空间，一个字典结构，映射到object space
    dict *expires;          // 键的过期时间，key为键，value为过期时间的毫秒级 UNIX 时间戳
    dict *blocking_keys;    // 处于阻塞状态的键和相应的client（主要用于List类型的阻塞操作）
    dict *ready_keys;       // 数据准备后后可以解除阻塞状态的键（主要用于List类型的阻塞操作）
    dict *watched_keys;     // 被watch命令监控的key和相应client
    int id;                 // 数据库ID标识
    long long avg_ttl;      // 数据库内所有键的平均TTL（生存时间）
    list *defrag_later;     // 逐一尝试整理碎片的关键名称列表
} redisDb;
```

根据上述结构，是否就可以构想出redis的宏观实现了。其中dict是我们关心的重点，存储实际数据，是一个k-v的字典结构，维护key space和object space的映射关系。其中key是一个sds（simple dynamic string）结构，下文strings数据类型时会详细介绍，vlaue是一个robj结构，如下所示：

```c
/* Object types */
#define OBJ_STRING 0
#define OBJ_LIST 1
#define OBJ_SET 2
#define OBJ_ZSET 3
#define OBJ_HASH 4

/* Objects encoding. Some kind of objects like Strings and Hashes can be
 * internally represented in multiple ways. The 'encoding' field of the object
 * is set to one of this fields for this object. */
// 最原生的表示方式。其实只有string类型才会用，即sds（simple dynamic string）
#define OBJ_ENCODING_RAW 0     /* Raw representation */
// 直接把string存成了long型
#define OBJ_ENCODING_INT 1     /* Encoded as integer */
#define OBJ_ENCODING_HT 2      /* Encoded as hash table */
#define OBJ_ENCODING_ZIPMAP 3  /* Encoded as zipmap */
#define OBJ_ENCODING_LINKEDLIST 4 /* Encoded as regular linked list */
#define OBJ_ENCODING_ZIPLIST 5 /* Encoded as ziplist */
#define OBJ_ENCODING_INTSET 6  /* Encoded as intset */
#define OBJ_ENCODING_SKIPLIST 7  /* Encoded as skiplist */
// 一种特殊的嵌入式的sds，用于优化短字符串存储
#define OBJ_ENCODING_EMBSTR 8  /* Embedded sds string encoding */
#define OBJ_ENCODING_QUICKLIST 9 /* Encoded as linked list of ziplists */

#define LRU_BITS 24
typedef struct redisObject {
    unsigned type:4; // 对象数据类型，4个字节，取值见头部注释
    unsigned encoding:4; // 对象内部编码方式，4个字节，取值见头部注释
    // 24个bit，以秒为单位存储了对象新建或者更新时的unix time，用于LRU/LFU替换算法用
    unsigned lru:LRU_BITS; /* LRU time (relative to global lru_clock) or
    					   * LFU data (least significant 8 bits frequency	
                           * and most significant 16 bits access time)
                           */
    int refcount; // 1、引用计数，用于内存回收 2、共享对象
    void *ptr; // 数据指针，指向真正的数据
} robj;
```

根据上述结构，是否就可以想象出Redis是如何兼容多种数据结构的？redisObject就是一种通用结构，根据type、encoding决定了value的实际存储结构，再由数据指针ptr指向数据地址

**type和encoding有什么区别？**

type是对外暴露的数据类型，而encoding是Redis根据k-v键值对情况决定采用的实际存储结构，是一种存储结构上的优化手段，详见下文五种数据类型介绍。

**refcount引用计数如何用于内存回收？**

创建对象时，初始化为1。当对象被一个新程序使用时+1，不再被一个程序使用时-1，为0时表示可以回收。

**引用计数作为内存回收会存在循环引用的问题，Redis是如何避免的？**

robj只有一个指向底层数据结构的ptr指针，对象之间不存在引用关系。而ptr指针寻址时，除了Redis共享的0~9999的数值字符串对象外，别的对象ptr指针都对应唯一的地址

**为什么Redis只共享0~9999的数字字符串对象？**

Redis在初始化服务器时，会创建一万个字符串对象，包含0~9999的整数值，后续使用不再创建对象，通过refcount+1共享使用。至于为什么不共享其他对象，是因为需要验证共享对象和目标对象是否完全一致。而复杂度高的对象验证成本越高，消耗CPU时间也越多。因此，仅共享整数值的字符串对象。

> - [Redis内部数据结构详解(3)——robj](http://zhangtielei.com/posts/blog-redis-robj.html)
> - [如何解决引用计数的循环引用问题](https://blog.csdn.net/weixin_43958091/article/details/105163643)

# 数据类型

## String

### 原理探索

Redis是由C语言编写的，但并未直接使用C语言的字符串结构，即字符数组。而是对其进行了封装，自定义了一种简单动态字符串（Simple Dynamic String，SDS）的抽象结构，如下所示：

```c
struct sdshdr {
    // 用于记录buf数组中使用的字节的数目，和SDS存储的字符串的长度相等
    int len;
    // 用于记录buf数组中没有使用的字节的数目
    int free;
    // 字节数组，用于储存字符串
    char buf[];
};
```

可以看出SDS结构很简单，一块连续可用的内存空间+两个记录长度的len、free，buf的大小等于len+free+1，多余的1个字节用于存储'\0'，表示字符串结尾。

**封装的好处？**

- 常数复杂度获取字符串长度
- 杜绝缓冲区buf溢出

**如何进行内存管理，杜绝缓冲区溢出的？**

为了避免缓冲区溢出，当然需要在空间不足时进行扩容。那么Redis是如何进行扩容，请看以下示例：

|          | 插入：hello | 修改后：hello world |
| :------: | :---------: | ------------------- |
| 需要空间 |    5+1=6    | 5+6+1=12            |
| 实际分配 |    5+1=6    | (5+6)*2+1=23        |

从修改后的空间分配情况，我们可以看出Redis分配了与len等大的未使用空间。但需要注意的是，当SDS修改后的长度大于1M，只会额外分配1M的未使用空间。用一句话总结，即**分配等大但不超过1M的未使用空间**。

**那么为什么要采用这种“空间预分配”机制，有什么好处呢？**

如果数据被修改，则说明这个数据很可能会被再次修改，如果能够提前分配多余的空间，那么下次变化的时候很可能就不需要再次分配空间，可以减少由于修改字符串带来的内存重分配次数，即最多N次内存分配。1M作为边界值是为了避免由于“空间预分配”造成的内存浪费。

**反之，字符串长度缩短，SDS是如何处理的？**

Redis采用了“惰性空间释放”机制，并未直接释放未使用空间，仅修改len和free值。避免了字符串缩短带来的内存重分配情况，多余空间可用于后续字符串增加的使用。

如果需要时，SDS也提供了直接释放未使用空间的API。

**SDS是如何兼容C语言字符串，且保证二进制安全的？**

C语言中，使用’\0’判定一个字符串的结尾。如果保存的字符串内存在’\0’，C语言自会识别前面的数据，后面的就会被忽略掉，这样是不安全的。而Redis使用了独立的len，可以保证即使存储的数据中有’\0’这样的字符，也可以准确读取。

需要注意的是buf数组存储的不是字符，而是二进制数组。Redis只关心二进制化的字符串，不关心具体格式，只会严格的按照二进制的数据存取，不会妄图以某种特殊格式解析数据。所以Redis的string可以支持各种类型（图片、视频、静态文件、css文件等）。

由于SDS的buf的定义和C字符串完全相同，因此很多的C字符串的操作都是适用于SDS->buf的。比如当buf里面存的是文本字符串的时候，printf函数，也完全可以试用。这样，Redis就不需要为所有的字符串的处理编写自己的函数，大多数通过调用C语言的函数就可以。

> - [Redis 基本操作 ——String (原理篇)](https://www.miaoerduo.com/2016/04/25/redis-string-principles/)
> - [Redis 基本操作 ——String (实战篇)](https://www.miaoerduo.com/2016/05/01/redis-string-practice/)
> - [Redis 设计与实现](http://redisbook.com/)

### 场景应用

- 验证码
- session
- 计数器
- 分布式锁
- 基于位操作
  - 活跃用户统计
  - 用户在线状态
  - 用户签到

## List

### 原理探索

#### ziplist和linkedlist

列表的实现无非就是数组、链表，在Redis 3.2之前，Redis的列表底层由ziplist、linkedlist实现，对应数组结构和链表结构，默认使用ziplist。

重点介绍下ziplist，**一系列特殊编码的连续内存块组成的顺序存储结构**，一种基础结构，quicklist、hash中都有使用，其结构如下所示：

![图1 整体布局](https://sheungxin.github.io/notpic/bVbtiqI)

```c
typedef struct ziplist{
     /*ziplist分配的内存大小*/
     uint32_t bytes;
     /*达到尾部的偏移量*/
     uint32_t tail_offset;
     /*存储元素实体个数*/
     uint16_t length;
     /*存储内容实体元素，zlentry数组*/
     unsigned char* content[];
     /*尾部标识，值为0xFF*/
     unsigned char end;
}ziplist;

/*元素实体所有信息, 仅仅是描述使用, 内存中并非如此存储*/
typedef struct zlentry {
     /*prevrawlen表示前一个zlentry长度，prevrawlensize表示prevrawlen定义长度*/
    unsigned int prevrawlensize, prevrawlen;
     /*len表示当前zlentry长度，lensize表示len定义长度*/
    unsigned int lensize, len;
     /*头部长度即prevrawlensize + lensize*/
    unsigned int headersize;
     /*元素内容编码，字节数组或整数*/
    unsigned char encoding;
     /*元素实际内容*/
    unsigned char *p;
}zlentry;
```

其优势在于内存空间连续、节省空间，缺点在于不擅长修改操作，会造成频繁的申请和内存释放，有可能引发连锁更新问题（prevrawlen采用变长编码）。

针对ziplist的不足，Redis 3.2之前在以下任一条件下转换为linkedlist，转换条件如下：

- 列表对象保存的所有字符串元素的长度都大于 64 字节（server.list_max_ziplist_value）
- 列表对象保存的元素数量大于 512 个（server.list_max_ziplist_entries）

linkedlist的优势在于插入复杂度低，缺点也很明细，内容开销大，需要额外维护两个指针，且内存地址不连续，容易产生内存碎片。

#### quicklist

针对以上两种结构的不足，在Redis 3.2及以后，新引入了quicklist的数据结构，实际上就是ziplist和linkedlist的结合，定义如下：

![quicklist结构](https://sheungxin.github.io/notpic/2018060110155534)

```c
typedef struct quicklist {
    quicklistNode *head;        // 指向quicklist的头部
    quicklistNode *tail;        // 指向quicklist的尾部
    unsigned long count;        // 列表中所有数据项的个数总和
    unsigned int len;           // quicklist节点的个数，即ziplist的个数
    int fill : 16;              // ziplist大小限定，由list-max-ziplist-size给定
    unsigned int compress : 16; // 节点压缩深度设置，由list-compress-depth给定
} quicklist;
```

- quicklist的节点node实际上就是一个个ziplist，然后把node用双向指针连接起来，很明显ziplist、linkedlist的结合体。
- fill正数表示每个节点元素个数，-1~-5，表示每个节点可存放的字节数4kb~64kb，默认值-2
- compress取值范围0~N，表示quicklist两端各有N个节点不压缩(中间数据访问率较低，压缩减小空间占用，但增加访问开销)，0表示不压缩

quicklistNode定义如下：

```c
typedef struct quicklistNode {
    struct quicklistNode *prev;  // 指向上一个ziplist节点
    struct quicklistNode *next;  // 指向下一个ziplist节点
    unsigned char *zl;           // 数据指针，如果没有被压缩，就指向ziplist结构，反之指向quicklistLZF结构 
    unsigned int sz;             // 表示指向ziplist结构的总长度(内存占用长度)
    unsigned int count : 16;     // 表示ziplist中的数据项个数
    unsigned int encoding : 2;   // 编码方式，1--ziplist，2--quicklistLZF
    unsigned int container : 2;  // 预留字段，存放数据的方式，1--NONE，2--ziplist
    unsigned int recompress : 1; // 解压标记，当查看一个被压缩的数据时，需要暂时解压，标记此参数为1，之后再重新进行压缩
    unsigned int attempted_compress : 1; // 测试相关
    unsigned int extra : 10; // 扩展字段，暂时没用
} quicklistNode;
```

### 场景应用

- 点到点的消息队列，建议使用brpop和blpop堵塞读取。brpop和blpop可以接收多个键，按照key的顺序进行读取，只要有一个key有值就弹出该元素，利用此特性可以实现优先级队列
- 定时计算更新的排行榜
- 最新列表，例如：点赞列表、评论列表，缺点在于：不适用频繁更新的分页场景、不适用时间范围查找的最新列表

**如何实现堵塞？**

在介绍redisDb时，其中维护了一个字典结构blocking_keys，key是堵塞的键，值是一个链表，保存所有因这个键堵塞的客户端信息，客户端状态为“正在堵塞”，并记录最长堵塞时间。

另外，redisDb中还维护了另一个链表结构ready_keys，存放数据准备好后可以解除阻塞状态的键。

服务端在每次的事件循环中处理完客户端请求之后，会遍历ready_keys链表，并从blocking_keys链表当中找到对应的client，进行响应。

**为什么不能使用Zset替代？**

Zset内存占用相较List数倍之多，大数据量场景不可取

## Hash

### 原理探索

#### zipmap

Hash的实现首先想到的肯定是字典结构，然而Redis为了节省空间设计了一种字符串-字符串映射结构zipmap，通过一块连续的内存空间来依次存放key-value，如下所示：

![这里写图片描写叙述](https://sheungxin.github.io/notpic/20160410095737434)

- zmlen：1个字节，小于254表示键值对数量，反之计算元素数量需要遍历整个结构
- key-value：
  - key length：key的长度，小于254占用一个字节，大于等于254，使用5个字节，第一个字节为254，后4个字节代表实际长度
  - key：存储key
  - value length：value的长度，类似key length
  - free：value修改后可能会产生空闲空间，并未直接回收，用free记录空闲字节数，一个字节表示。不用担心不够使用，ZIPMAP_VALUE_MAX_FREE会限制value最大空间，默认4字节
  - value：存储value，可能存在空闲空间
- end：结尾符，一个字节，固定为0xFF，十进制为255

从zipmap的数据结构可以看出，key-value的查找只能通过依次遍历每一个key-value，且插入、修改、删除操作都有可能造成空间的重新分配。因此，zipmap不适合存放大量的key-value对。

#### hashtable

既然zipmap不适合存放大量的key-value对，Redis在以下任一条件下会转化为dict字典结构，转化条件如下：

- 键值对中键和值任一长度大于64字节(hash_max_ziplist_value或者hash-max-ziplist-entries for Redis >= 2.6)
- 哈希对象保存的键值对数量大于512个(hash_max_ziplist_entries或者hash-max-ziplist-value for Redis >= 2.6)

dict字典结构图，如下所示：

![dict结构](https://sheungxin.github.io/notpic/20170802160443789)

详细定义如下所示：

```c
// 字典结构
typedef struct dict {
    dictType *type;  // 类型特定函数，保存一些用于操作特定类型键值对的函数
    void *privdata;  // 私有数据
    dictht ht[2];    // 2个哈希表
    /*
    * 1、rehash进度，-1表示没有进行
    * 2、成倍的扩容或收缩
    * 3、支持渐近式rehash，添加在新的哈希表上进行，删除、查找、更新在两个哈希表上进行
    */
    long rehashidx; /* rehashing not in progress if rehashidx == -1 */
    // 目前正在运行的安全迭代器的数量
    unsigned long iterators; /* number of iterators currently running */
} dict;

// hash表结构
typedef struct dictht {

    // 哈希表数组
    dictEntry **table;

    // 哈希表大小
    unsigned long size;

    // 哈希表大小掩码，用于计算索引值，总是等于 size - 1
    unsigned long sizemask;

    // 哈希表已有节点的数量
    unsigned long used;

} dictht;

// 每一个具体的键值对
typedef struct dictEntry {
    void *key; // 键
    union {
        void *val;
        uint64_t u64;
        int64_t s64;
        double d;
    } v; // 值
    // 指向下一个结点，因为hash值有可能冲突，冲突的时候链表形式保存在同一个索引后边
    struct dictEntry *next;
} dictEntry;
```

**dict如何实现遍历？**

首先了解一下反向二进制，例如数组长度为8的数组下标二进制表示如下：

```java
000 --> 001 --> 010 --> 011 --> 100 --> 101 --> 110 --> 111 
```

转换为反向二进制后如下：

```java
000 --> 100 --> 010 --> 110 --> 001 --> 101 --> 011 --> 111
// 对应十进制如下    
 0  -->  4  -->  2  -->  6  -->  1  -->  5  -->  3  -->  7 
```

hash的扩展都是翻倍，即8*2=16，反向二进制后如下：

```java
0000 --> 1000 --> 0100 --> 1100 --> 0010 --> 1010 --> 0110 --> 1110 --> 0001 --> 1001 --> 0101 --> 1101 --> 0011 --> 1011 --> 0111 --> 1111   
 0   -->  8   -->  4   -->  12  -->  2   -->  10  -->  6   -->  14  -->   1  -->  9   -->   5  -->  13  -->  3   -->  11  -->   7  -->  15
```

从上可以看出，转换后的反向二进制，依次相邻的两个差值为8。而hash扩容，每个数组下标中数据被拆分为两份，一份保持位置不变，另一份放入当前下标+原数组长度（这里原数组长度为8）的位置，反向二进制后刚好把拆分后的两个下标依次放在了一起。

正因为扩容后对应的两个下标刚好在一起，在两个数组切换后，刚好可以忽略之前已经遍历过的下标位，例如：010遍历后，刚好rehash扩容到16，直接从0110开始即可，0、4、2刚好对应0、8、4、12、2、10，只是把已经遍历的数组拆分到两个不同的下标。**可以保证扩容时遍历不会遗漏元素且元素不会被重复遍历；缩小时由于相邻的两个节点可能只遍历了一个，造成切换时较小的元素重复遍历，但不会遗漏元素**

> - [Redis内置数据结构之压缩字典zipmap](https://www.cnblogs.com/zhchoutai/p/7182603.html)
> - [Redis源码剖析-dict字典](https://blog.csdn.net/harleylau/article/details/77899179)

### 场景应用

存储属性频繁变化的对象，例如：购物车场景。不常变化属性的对象建议使用string+json，序列化、存储结构成本均比较低，更轻量化。

## Set

### 原理探索

Java中HashSet的实现就是内部构建了一个HashMap结构，value是一个固定值，Redis同样使用了hashtable结构，可参考Hash中hashtable结构。

除了hashtable，Redis对元素为整数的Set做了优化，使用了**intset结构，一个由整数组成的有序集合，最多只能存储512个元素（server.set_max_intset_entries）**。

```c
typedef struct intset {
    uint32_t encoding; // 编码方式，支持int16、int32、int64编码，表示元素使用2/4/8个字节存储
    uint32_t length; // 集合包含的元素数量
    int8_t contents[]; // 有序数组
} intset;
```

数据添加过程如下：

![img](https://sheungxin.github.io/notpic/redis_intset_add_example.png)

从上图过程可以得出以下结论：

- intset是一个有序数组，支持二分查找元素
- 插入数据有可能引起intset重组，即编码升级（删除不支持编码降级，但可能会移动元素）

**Set不是无序集合吗，intset如何实现无序的？**

有序数组可以支持二分查找，查找效率更好。无序是通过函数intsetRandom随机选取元素实现

**inset与ziplist区别？**

- ziplist可以存储任意二进制串，而intset只能存储整数
- ziplist是无序的，而intset是从小到大有序的。因此，在ziplist上查找只能遍历，而在intset上可以进行二分查找，性能更高
- ziplist可以对每个数据项进行不同的变长编码（每个数据项前面都有数据长度字段`len`），而intset只能整体使用一个统一的编码（`encoding`）

> [Redis内部数据结构详解(7)——intset](https://blog.csdn.net/yellowriver007/article/details/79021147)

### 场景应用

- 构建对象之间关系，例如好友、粉丝、关注、感兴趣人集合（支持并交差运算）
- 随机展示
- 黑/白名单

## Zset

### 原理探索

Zset即有序集合，Redis同样提供了两种实现方式，**ziplist和zset结构**。

#### ziplist

ziplist结构上文List类型已有介绍，这里不再详细描述，主要差异在于元素按score值从小到大排序，value、score依次相邻，如下所示：

```c
          |<--  element 1 -->|<--  element 2 -->|<--   .......   -->|

+---------+---------+--------+---------+--------+---------+---------+---------+
| ZIPLIST |         |        |         |        |         |         | ZIPLIST |
| ENTRY   | member1 | score1 | member2 | score2 |   ...   |   ...   | ENTRY   |
| HEAD    |         |        |         |        |         |         | END     |
+---------+---------+--------+---------+--------+---------+---------+---------+
```

缺点很明显，只适合存储少量数据，在以下任一条件下转化为zset：

- 元素个数超过128(zset-max-ziplist-entries)
- 任一数据长度超过64字节(zset-max-ziplist-value)

#### zset

zset同时使用了**字典dict和跳表zskiplist**两种结构，如下所示：

![img](https://sheungxin.github.io/notpic/graphviz-75ee561bcc63f8ea960d0339768aec97b1f570f0.png)

```c
typedef struct zset {
    dict *dict; // 字典参考hashe中hashtable实现，zscore作为value，时间复杂度O(1)
    zskiplist *zsl; // 跳表
} zset;
            
typedef struct zskiplist {
    struct zskiplistNode *header, *tail; // 头尾节点，对应结构zskiplistNode
    unsigned long length; // 节点数量，不包含空的头指针
    int level; // 层数最大节点的层数
} zskiplist;

// 跳表节点
typedef struct zskiplistNode {
    robj *obj; // 节点数据，一个string robj
    double score; // 数据对应的分数
    struct zskiplistNode *backward; // 指向链表的前一个节点，集合forward在第一层是一个双向链表
    // 数组长度代表层数，层数随机
    struct zskiplistLevel {
        struct zskiplistNode *forward; // 指向各层链表下一个节点的指针
        unsigned int span; // 当前指针跨越多少个节点，用于排名
    } level[];
} zskiplistNode;

#define ZSKIPLIST_MAXLEVEL 32 // 常量，最大层数
#define ZSKIPLIST_P 0.25 // 常量，随机数与之比较，用于计算每个节点的随机层数
// 随机层数算法
randomLevel()
    level := 1
    // random()返回一个[0...1)的随机数
    while random() < p and level < MaxLevel do
        level := level + 1
    return level
```

下图展示了skiplist的插入过程：

![skiplist插入形成过程](https://sheungxin.github.io/notpic/skiplist_insertions.png)

- 注意头结点不存放数据，每次查找从头结点开始，根据当前最大层数level开始逐层寻找
- 先从高层链表中查找，然后逐层降低，最终降到第1层链表来精确地确定数据位置

- 每一个节点的层数（level）是随机出来的，而且新插入一个节点不会影响其它节点的层数，只需要修改插入节点前后的指针，降低了插入操作的复杂度

skiplist的好处：

- 范围查找简单，第一层链表是一个双向结构
- 插入和删除只需要修改相邻节点指针
- 算法实现相对简单，时间复杂度O(logn)，内存占用也在接受范围内

**skiplist如何实现排名？**

zskiplistLevel里除了后向指针，还包含一个span，表示当前指针跨越多少个节点（不包含起始节点），通过依次累加所有后向指针对应节点中的span，并减1（rank排名以0起始），即为实际排名。倒序排名，使用skiplist长度length减去累加值即可。

> [Redis内部数据结构详解(6)——skiplist](https://blog.csdn.net/yellowriver007/article/details/79021103)

### 场景应用

- 排行榜，例如：当日点击榜、七日搜索榜等
- 权重队列，例如根据时间排序的新闻列表等
- [延迟队列](https://mp.weixin.qq.com/s/DUMJVRJAPdTFpHRn90qA6g)

# 高级应用

## 订阅与发布

Redis 通过 PUBLISH 、 SUBSCRIBE、PSUBSCRIBE 等命令实现了订阅与发布，提供了**频道和模式**两种信息匹配机制，如下所示：

![img](https://sheungxin.github.io/notpic/graphviz-49c2b60cc3c2b52ec1623fbd8a9002eb6f335a54.svg)

即通过频道channel的精确匹配、模糊匹配两种方式。

**Redis是如何实现的呢？**

首先看一下Redis从结构上是如何定义以上两种匹配机制的，如下所示：

```c
struct redisServer {
    ...
    dict *pubsub_channels; // 用于保存订阅频道的信息，精确匹配
    list *pubsub_patterns; // 链表中保存着所有和订阅模式相关的信息，模糊匹配
    ...
};

// pubsub_patterns中每个节点包含一个 redis.h/pubsubPattern 结构
typedef struct pubsubPattern {
    redisClient *client;
    robj *pattern;
} pubsubPattern;

```

采用了字典结构和链表结构，字典结构用于定义channel与client的直接映射关系，链表结构用于存储channel与client模糊匹配规则。当发布消息时，遍历以上两个数据结构，找出匹配的client即可，伪代码如下：

```c
// 发布消息
def PUBLISH(channel, message):
    // 遍历所有订阅频道 channel 的客户端
    for client in server.pubsub_channels[channel]:
        // 将信息发送给它们
        send_message(client, message)

    // 取出所有模式，以及订阅模式的客户端
    for pattern, client in server.pubsub_patterns:
        // 如果 channel 和模式匹配
        if match(channel, pattern):
            // 那么也将信息发给订阅这个模式的客户端
            send_message(client, message)
```

需要注意若channel A和client A同时存在于pubsub_channels和pubsub_patterns，或者在pubsub_patterns存在多个匹配规则，当消息发布到channel A时，client A会收到多条内容重复的消息。

**如何退订频道或模式？**

从以上两个结构中删除对应的client即可，使用 UNSUBSCRIBE、PUNSUBSCRIBE 命令可以退订指定的频道或模式。

**能否使用Redis的发布/订阅替代MQ**

是否可以替代，首先要清楚Redis的发布/订阅与MQ存在的差异，如下所示：

- Redis无法对消息持久化存储，一旦消息被发送，如果没有订阅者接收，消息会丢失
- Redis未提供消息可靠性保证

Redis不是专门做发布订阅的，功能相对简单很多，是否可替代MQ使用还是要根据实际业务场景，例如：业务中的异步通知、参数刷新加载等

> - [订阅与发布](https://redisbook.readthedocs.io/en/latest/feature/pubsub.html)
> - [redis实现消息队列&发布/订阅模式使用](https://www.cnblogs.com/qlqwjy/p/9763754.html)

## Keyspace Notifications

在Redis 2.8.0版本起，加入了“Keyspace notifications”（即“键空间通知”）的功能，使得客户端可以通过订阅频道或模式， 来接收那些以某种方式改动了 Redis 数据集的事件。例如：

- 所有修改键的命令
- 所有接收到 LPUSH key value [value …] 命令的键
- `0` 号数据库中所有已过期的键

对于每个修改数据库的操作，键空间通知都会发送两种不同类型的事件。比如说，对 `0` 号数据库的键 `mykey` 执行 DEL key [key …] 命令时， 系统将分发两条消息， 相当于执行以下两个 PUBLISH channel message 命令：

```c
PUBLISH __keyspace@0__:mykey del
PUBLISH __keyevent@0__:del mykey
```

订阅第一个频道 `__keyspace@0__:mykey` 可以接收 0 号数据库中所有修改键 `mykey` 的事件， 而订阅第二个频道 `__keyevent@0__:del` 则可以接收 0 号数据库中所有执行 del 命令的键。

但需要注意的是Redis 目前的订阅与发布功能采取的是发送即忘（fire and forget）策略， 所以如果需要可靠事件通知（reliable notification of events）， 那么目前的键空间通知可能并不适合：**当订阅事件的客户端断线时， 它会丢失所有在断线期间分发给它的事件**。

**如何使用？**

因为开启键空间通知功能需要消耗一些 CPU ， 所以在默认配置下， 该功能处于关闭状态。可以通过修改 redis.conf 文件， 或者直接使用 `CONFIG SET` 命令来开启或关闭键空间通知功能：

- 当 notify-keyspace-events 选项的参数为空字符串时，功能关闭。

- 当 notify-keyspace-events 选项的参数不是空字符串时，功能开启，参数组合如下：

  | 字符 | 发送的通知                                                   |
  | ---- | ------------------------------------------------------------ |
  | `K`  | 键空间通知，所有通知以 `__keyspace@<db>__` 为前缀            |
  | `E`  | 键事件通知，所有通知以 `__keyevent@<db>__` 为前缀            |
  | `g`  | `DEL` 、 `EXPIRE` 、 `RENAME` 等类型无关的通用命令的通知     |
  | `$`  | 字符串命令的通知                                             |
  | `l`  | 列表命令的通知                                               |
  | `s`  | 集合命令的通知                                               |
  | `h`  | 哈希命令的通知                                               |
  | `z`  | 有序集合命令的通知                                           |
  | `x`  | 过期事件：每当有过期键被删除时发送                           |
  | `e`  | 驱逐(evict)事件：每当有键因为 `maxmemory` 政策而被删除时发送 |
  | `A`  | 参数 `g$lshzxe` 的别名                                       |

输入的参数中至少要有一个 `K` 或者 `E` ， 否则的话， 不管其余的参数是什么， 都不会有任何通知被分发。

**过期通知产生的时机** 

Redis 产生 `expired` 通知的时间为过期键被删除的时候， 而不是键的生存时间变为 `0` 的时候。

> [键空间通知（keyspace notification）](http://redisdoc.com/topic/notification.html)

## HyperLogLog

HyperLogLog即基数估算，提供不精确的去重计数，存在以下的特点：

- 极少的内存来统计巨量的数据，在 Redis中实现的 HyperLogLog，只需要12K内存就能统计2^64个数据
- 计数存在一定的误差，误差率整体较低，标准误差为 0.81% 
- 误差可以被设置辅助计算因子进行降低

**Redis是如何实现HyperLogLog？**

概率论算法，源于伯努利实验，即抛硬币实验

- 抛硬币，出现正面记为一次实验，一次实验的抛硬币次数记为k
- 进行多轮n次实验，出现正面需要抛的最大次数记为k_max
- 已知最大次数k_max，估算试验次数n=2^(k_max)

通过分析以下命令来理解Redis中HyperLogLog的实现过程

```c
pfadd lgh golang
pfadd lgh python
pfadd lgh java
...
pfcount lgh    
```

在存入时，value会被hash成64位，64 位转为十进制就是：2^64，这也是为什么Redis使用12kb就能统计多达 2^64 个数。

本质上是一个bit数组，12kb内存按照每个桶6bit，刚好可以拆分为16384个桶。hash后的值需要落在某一个桶中，如何计算桶的下标？Redis中直接从右向左取hash后值的低14位，转化为十进制定位到桶的位置，2^14=16384刚好可以使用所有的桶且不浪费空间。

找到桶的位置，接着就需要在桶里填充值。取剩下50位首次出现1的下标index，和当前桶的k_max进行比较，k_max初始化为0，取较大值作为新的k_max并转化为而进行填充到桶中。每个桶6bit，最大可填充值为63，index最大值为50，所以也不存在溢出的情况。

所有的数据都放入后，每个桶都有一个k_max，pfcount时调用估算公式求调和平均数（倒数平均数）即可

**使用场景**

- 统计注册/访问IP数
- 统计在线用户数
- 统计页面实时UV数
- 统计用户每天搜索不同词条的个数

> [HyperLogLog 算法的原理讲解以及 Redis 是如何应用它的](https://www.cnblogs.com/linguanh/p/10460421.html)

## Redis事务

Redis 事务的本质是一组命令的集合，支持一次串行执行多个命令，且其他客户端提交的命令请求不会插入到事务执行命令中，分为开始事务、命令入队、执行事务三个阶段。但不能保证原子性，且没有回滚。

相关命令如下：

- watch key1 key2 ... : 监视一或多个key，如果在事务执行之前，被监视的key被其他命令改动，则事务被打断 （ 类似乐观锁 ）
- multi : 标记一个事务块的开始（queued）
- exec : 执行所有事务块的命令 （ 一旦执行exec后，之前加的监控锁watch会被取消掉）　
- discard : 取消事务，放弃事务块中的所有命令
- unwatch : 取消watch对所有key的监控

注意事项：

- 若在事务队列中存在命令性错误（类似于java编译性错误），则执行EXEC命令时，所有命令都不会执行
- 若在事务队列中存在语法性错误（类似于java的1/0的运行时异常），则执行EXEC命令时，其他正确命令会被执行，错误命令抛出异常
- 一但EXEC执行事务，无论事务是否执行成功， WARCH 对变量的监控都将被取消

> [Redis之Redis事务](https://www.cnblogs.com/DeepInThought/p/10720132.html)

## 布隆过滤器

**什么是布隆过滤器？**

布隆过滤器（Bloom Filter）是由Howard Bloom在1970年提出的一种比较巧妙的概率型数据结构，它可以告诉你某种东西**一定不存在**或者**可能存在**。本质上是一个bit数组，如下所示：

![image-20201010095508622](https://sheungxin.github.io/notpic/image-20201010095508622.png)

通过hash后计算得到数组下标并记为1，这样一条数据只占用1bit空间。判断数据是否存在时，同样通过hash后计算的下标，判断bit数组对应下标位是否为1。

但由于hash算法存在碰撞的可能，不同的数据可能对应同一个下标。所以通过使用不同的hash算法和增加bit数组大小提高精度，例如上图使用了三种不同的哈时候算法。

虽然使用多种hash算法和增加bit数组大小可以提高精度，但并不能完全避免hash碰撞。因为，只能断定某个元素一定不存在（任意一个位为0）或者可能存在（都为1，可能是hash碰撞造成的）。

**Redis中如何使用？**

Redis 4.0之前可以通过位图操作实现，但Redis 4.0版本提供了插件功能，官方提供了布隆过滤器插件，加载到Redis Server即可。

基本命令如下：

- bf.add：添加元素到布隆过滤器中，类似于集合的sadd命令，不过bf.add命令只能一次添加一个元素，如果想一次添加多个元素，可以使用bf.madd命令
- bf.exists：判断某个元素是否在过滤器中，类似于集合的sismember命令，不过bf.exists命令只能一次查询一个元素，如果想一次查询多个元素，可以使用bf.mexists命令
- bf.reserve：自定义布隆过滤器，设置准确度，参数如下：
  - key：键
  - error_rate：期望错误率，期望错误率越低，需要的空间就越大
  - capacity：初始容量，当实际元素的数量超过这个初始化容量时，误判率上升

**布隆过滤器的应用场景**

- 解决缓存穿透的问题

  一般情况下，先查询缓存是否有该条数据，缓存中没有时，再查询数据库。当数据库也不存在该条数据时，每次查询都要访问数据库，这就是缓存穿透。缓存穿透带来的问题是，当有大量请求查询数据库不存在的数据时，就会给数据库带来压力，甚至会拖垮数据库。

  可以使用布隆过滤器解决缓存穿透的问题，把已存在数据的key存在布隆过滤器中。当有新的请求时，先到布隆过滤器中查询是否存在，如果不存在该条数据直接返回；如果存在该条数据再查询缓存、查询数据库（通过设置精度，误判概率在可控范围内，如果不允许误判，再查询缓存/DB，缓存仅缓存DB查询后热点数据即可）

- 黑名单校验

  发现存在黑名单中的，就执行特定操作。比如：识别垃圾邮件，只要是邮箱在黑名单中的邮件，就识别为垃圾邮件。假设黑名单的数量是数以亿计的，存放起来就是非常耗费存储空间的，布隆过滤器则是一个较好的解决方案。把所有黑名单都放在布隆过滤器中，在收到邮件时，判断邮件地址是否在布隆过滤器中即可（存在一定程度的误判）

> - [详细解析Redis中的布隆过滤器及其应用](https://www.cnblogs.com/heihaozi/p/12174478.html)
>
> -  [Redis 布隆过滤器](https://www.cnblogs.com/happydreamzjl/p/11834277.html)

## Redis GEO

Redis GEO 主要用于存储地理位置信息，并对存储的信息进行操作，该功能在 Redis 3.2 版本新增。

Redis GEO 操作方法有：

- geoadd：添加地理位置的坐标
- geopos：获取地理位置的坐标
- geodist：计算两个位置之间的距离
- georadius：根据用户给定的经纬度坐标来获取指定范围内的地理位置集合
- georadiusbymember：根据储存在位置集合里面的某个地点获取指定范围内的地理位置集合
- geohash：返回一个或多个位置对象的 geohash 值

**Redis GEO是如何实现的呢？**

先看如下一组命令，如下所示：

```c
// 添加两组车辆坐标
> geoadd cars:locations 120.346111 31.556381 1 120.375821 31.560368 2 

// 使用zset的zrange命令查看数据项
> ZRANGE cars:locations 0 -1 WITHSCORES
1) "1"
2) "4054421060663027"
3) "2"
4) "4054421167795118"
```

根据上述结果可以推断出Redis GEO底层使用zset结构进行存储，执行geoadd命令相当于把坐标经纬度进行编码后的值作为zadd的score，如下所示：

```c
ZADD cars:locations 4054421060663027 1
ZADD cars:locations 4054421167795118 2
```

知道Redis GEO的存储结构，就可以初步推算出geo*相关命令是如何实现的，暂不做深入探究。

**Redis是如何对经纬度进行编码的？**

Redis使用了geohash对经纬度信息进行编码

> - [Redis GEO & 实现原理深度分析](https://blog.csdn.net/weixin_34415923/article/details/88004243)
> - [GeoHash核心原理解析](https://www.cnblogs.com/LBSer/p/3310455.html)
> - [深入浅出空间索引：为什么需要空间索引](https://www.cnblogs.com/LBSer/p/3392491.html)
> - [深入浅出空间索引：2](https://www.cnblogs.com/LBSer/p/3403933.html)

## Redis Stream

基于Reids的消息队列实现有很多种，例如：

- PUB/SUB，订阅/发布模式
- 基于List的 LPUSH+BRPOP 的实现
- 基于Sorted-Set的实现

每一种实现，都有典型的特点和问题。Redis Stream 是 Redis 5.0 版本新增加的数据结构，是Redis对消息队列（MQ，Message Queue）的完善实现，包括但不限于：

- 消息ID的序列化生成
- 消息遍历
- 消息的阻塞和非阻塞读取
- 消息的分组消费
- 未完成消息的处理
- 消息队列监控

Redis Stream的结构如下图所示，有一个消息链表，将所有加入的消息都串起来，每个消息都有一个唯一的ID和对应的内容。消息是持久化的，Redis重启后，内容还在。

![img](https://sheungxin.github.io/notpic/en-us_image_0167982791.png)

Stream的消费模型借鉴了kafka的消费分组的概念，它弥补了Redis Pub/Sub不能持久化消息的缺陷。但是它又不同于kafka，kafka的消息可以分partition，而Stream不行。如果非要分parition的话，得在客户端做，提供不同的Stream名称，对消息进行hash取模来选择往哪个Stream里塞。

> - [基于Redis实现消息队列典型方案](http://www.hellokang.net/redis/message-queue-by-redis.html)
> - [如何看待Redis5.0的新特性stream？](https://www.zhihu.com/question/279540635)

## Redis管道技术

Redis是一种基于客户端-服务端模型以及请求/响应协议的TCP服务。这意味着通常情况下一个请求会遵循以下步骤：

- 客户端向服务端发送一个查询请求，并监听Socket返回，通常是以阻塞模式，等待服务端响应
- 服务端处理命令，并将结果返回给客户端

Redis 管道技术可以在服务端未响应时，客户端可以继续向服务端发送请求，并最终一次性读取所有服务端的响应，提高了redis服务的性能，对比如下：

```java
// 测试不使用管道，插入1000条数据耗时328毫秒
public static void testInsert() {  
    long currentTimeMillis = System.currentTimeMillis();  
    Jedis jedis = new Jedis("192.168.33.130", 6379);  
    for (int i = 0; i < 1000; i++) {  
        jedis.set("test" + i, "test" + i);  
    }  
    long endTimeMillis = System.currentTimeMillis();  
    System.out.println(endTimeMillis - currentTimeMillis);  
}  

// 测试管道，插入1000条数据耗时37毫秒
public static void testPip() {  
    long currentTimeMillis = System.currentTimeMillis();  
    Jedis jedis = new Jedis("192.168.33.130", 6379);  
    Pipeline pipelined = jedis.pipelined();  
    for (int i = 0; i < 1000; i++) {  
        pipelined.set("bb" + i, i + "bb");  
    }  
    pipelined.sync();  
    long endTimeMillis = System.currentTimeMillis();  
    System.out.println(endTimeMillis - currentTimeMillis);  
}  
```

## Redis脚本

Redis 脚本使用 Lua 解释器来执行脚本。 Redis 2.6 版本通过内嵌支持 Lua 环境。执行脚本的常用命令为 **EVAL**。

https://mp.weixin.qq.com/s/4Qpjx5IzbDQCH0S7RDRNrQ

# 内存管理

## 过期删除策略

redis过期键删除策略提供了如下两种方式：

- 惰性删除：在操作键时判断是否过期，决定是否删除。未操作的键不予处理，对内存不友好，可能长期占用内存
- 定期删除：默认每秒进行10次过期扫描，采用一种简单的贪心策略，如下：
  - 从过期字典redisDb.expires中随机最少20个key
  - 删除这N个key 中已经过期的 key
  - 如果选取的N个key中过期的key比率超过 1/4，那就重复步骤 1

<img src="https://sheungxin.github.io/notpic/161542_RP9V_2313177.png" alt="img" style="zoom:50%;" />

**如果某一时刻，有大量key同时过期怎么办？**

出现上述情况，定期扫描可能耗时较长。为了保证过期扫描不会出现循环过度，导致线程卡死现象，扫描时间的上限，默认不会超过 25ms（根据hz动态计算）。但是大量key同时过期，每秒10次，一次25ms，可能出现每秒250ms，每秒1/4的时间都在过期扫描。因此，在设置过期时间时，可以给过期时间设置一个随机范围，避免同一时刻过期。

**定期删除执行时间间隔是否可以调整？**

redis的定时任务默认是100ms执行一次，如果要修改这个值，可以在redis.conf中修改hz的值（默认10，即一秒10次）。提高hz的值将会更快的处理同时到期的key，但会占用更多的cpu。 hz的取值范围是1~500，通常不建议超过100。

**单线程的Redis如何运行定期删除任务？**

Redis 的定时任务会记录在一个称为最小堆的数据结构中，最快要执行的任务排在堆的最上方。在每个循环周期，Redis 都会将最小堆里面已经到点的任务立即进行处理。处理完毕后，将最快要执行的任务还需要的时间记录下来，这个时间就是接下来处理客户端请求的最大时长，若达到了该时长，则暂时不处理客户端请求而去运行定时任务。

**过期键在aof/rdb和复制功能时如何处理？**

- rdb
  - 生成rdb文件时，程序会对键进行检查，过期键不放入rdb文件
  - 载入rdb文件时，如果以主服务器模式运行，程序会对文件中保存的键进行检查，未过期的键会被载入到数据库中，而过期键则会忽略；如果以从服务器模式运行，无论键过期与否，均会载入数据库中，过期键会通过与主服务器同步而删除

- aof
  - 当服务器以aof持久化模式运行时，如果数据库中的某个键已经过期，但它还没有被删除，那么aof文件不会因为这个过期键而产生任何影响；当过期键被删除后，程序会向aof文件追加一条del命令来显式记录该键已被删除。
  - aof重写过程中，程序会对数据库中的键进行检查，已过期的键不会被保存到重写后的aof文件中

- 复制：当服务器运行在复制模式下时，从服务器的过期删除动作由主服务器控制
  - 主服务器在删除一个过期键后，会显式地向所有从服务器发送一个del命令，告知从服务器删除这个过期键
  - 从服务器在执行客户端发送的读命令时，即使碰到过期键也不会将过期键删除，而是继续像处理未过期的键一样来处理过期键
  - 从服务器只有在接到主服务器发来的del命令后，才会删除过期键

> - [Redis源码剖析（四）过期键的删除策略](https://blog.csdn.net/sinat_35261315/article/details/78976272?utm_medium=distribute.pc_relevant.none-task-blog-BlogCommendFromMachineLearnPai2-1.channel_param&depth_1-utm_source=distribute.pc_relevant.none-task-blog-BlogCommendFromMachineLearnPai2-1.channel_param)

## 回收算法

Redis使用的内存回收算法是**引用计数算法**和**LRU/LFU算法**。

### 引用计数算法

上文介绍Redis结构时提到refcount，如下所示：

```c
typedef struct redisObject {
    ...
    int refcount; // 1、引用计数，用于内存回收 2、共享对象
    ...
} robj;
```

在每个对象中定义了一个refcount变量用于引用计数，也提到了如何解决引用计数的循环依赖问题，详见上文。

### LRU算法

LRU是Least Recently Used的缩写，即最近最少使用，是一种常用的页面置换算法，选择最近最久未使用的页面予以淘汰。该算法赋予每个页面一个访问字段，用来记录该页面自上次被访问以来所经历的时间 t，当必须淘汰一个页面时，选择现有页面中其 t 值最大的，即最近最少使用的页面给予淘汰。LRU算法演示如下：

![img](https://sheungxin.github.io/notpic/251954349742220.png)

**Redis是如何实现LRU算法的？**

Redis使用的是一个近似LRU算法，随机选择5个键(maxmemory-samples，随机采样的精度。该数值配置越大，越接近于真实的LRU算法，但是数值越大，相应消耗也变高，对性能有一定影响，样本值默认为5)，选择一个最久未使用的键淘汰。

Redis3.0之后提供一个待淘汰候选key的pool，默认16个key，按空闲时间排序。更新时从Redis键空间随机选择N个key，分别计算它们的空闲时间idle，key只会在pool不满或者空闲时间大于pool里最小的时，才会进入pool，然后从pool中选择空闲时间最大的key淘汰掉。

上文介绍redisObject时提到了lru:LRU_BITS，用于LRU算法使用，如下：

```c
typedef struct redisObject {
    ...
    // 24个bit，用于LRU/LFU算法
    unsigned lru:LRU_BITS; /* LRU time (relative to global lru_clock) or
    					   * LFU data (least significant 8 bits frequency	
                           * and most significant 16 bits access time)
                           */ 
    ...
} robj;
```

先看看lru是怎么来以及如何变动的，如下：

```c
// 创建object对象时，会给lru属性赋值，再次访问对象时也会更新lru字段
robj *createObject(int type, void *ptr) {
    robj *o = zmalloc(sizeof(*o));
    o->type = type;
    o->encoding = OBJ_ENCODING_RAW;
    o->ptr = ptr;
    o->refcount = 1;

    /* Set the LRU to the current lruclock (minutes resolution). */
    o->lru = LRU_CLOCK();
    return o;
}

/* 
* - server.hz：定时任务频率，默认10，即一秒执行10次
* - LRU_CLOCK_RESOLUTION，代表了LRU算法的精度，默认值1000，即一个LRU的单位是1s
* - LRU_CLOCK含义：定时任务的间隔如果小于LRU的精度，表示服务器精度更高，
* 直接使用全局时钟server.lruclock（定时任务会更新），这样虽然得到的LRU_CLOCK虽然有误差，
* 但是在精度损失运行范围内，好处在于不用每次都执行getLRUClock增加额外开销
*/
define LRU_CLOCK() 
    ((1000/server.hz <= LRU_CLOCK_RESOLUTION) ? server.lruclock : getLRUClock())

/*  
* 定时任务服务器每次循环执行的时候，都会刷新server.lrulock
*/
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    ...
    server.lruclock = getLRUClock(); // 重新计算赋值
　　 ...
} 

/*  
* lruclock的计算，由于lruclock只有24bit，与LRU_CLOCK_MAX(二进制位都是1)进行与操作，
* 相当于直接丢失部分高位。在一定范围内丢弃的高位是一样的，不影响差值计算，即24bit随着数据增加直到溢出，
* （2^24-1）/60/60/24=194.17天，一个溢出周期在174.17天。当然由于key不可能都在溢出周期最开始进入，
* 所以174.17只是一个最大值。缓存数据更新非常频繁，已经够用，且针对溢出后得到的lruclock
* 小于之前的值的情况（溢出进位但丢失），在计算空闲时间时有特殊处理（见后续）
*/
unsigned int getLRUClock(void) {
    return (mstime()/LRU_CLOCK_RESOLUTION) & LRU_CLOCK_MAX;
} 
```

通过上述源码分析，lruclock是一个低24位的unixtime时间戳，那么如何计算空闲时间？如下所示：

```c
/*  
* 空闲时间：通过对象的lru和全局的LRU_CLOCK()的计算，最后乘以精度LRU_CLOCK_RESOLUTION（转化为毫秒）
*/
unsigned long long estimateObjectIdleTime(robj *o) {
    unsigned long long lruclock = LRU_CLOCK();
    if (lruclock >= o->lru) {
        // 溢出周期内，全局lruclock减去当前对象的lru并乘以精度LRU_CLOCK_RESOLUTION
        return (lruclock - o->lru) * LRU_CLOCK_RESOLUTION;
    } else {
        /* 
        * 一般不会发生，发生时证明redis中键的保存时间已经过了溢出周期，
        * 即键中保存的时钟反而大于当前全局时钟，就不能直接相减
        */
        return (lruclock + (LRU_CLOCK_MAX - o->lru))
                    LRU_CLOCK_RESOLUTION;
    }
}
```

### LFU算法

LFU全称是Least Frequently Used 表示按最近的访问频率进行淘汰，更加准确的判断一个key访问的热度。其实现借用了和LRU相同的lru字段，高16位存储访问时间戳、低8位存储访问频次。

```c
// 低16通过分钟时间戳对2^16进行取模
unsigned long LFUGetTimeInMinutes(void) {
    return (server.unixtime/60) & 65535;
}
```

逃逸时间的计算也很类似，如下：

```c
// ldt表示对象中时间戳，与当前时间戳比较，计算逻辑与LRU中一致
unsigned long LFUTimeElapsed(unsigned long ldt) {
   unsigned long now = LFUGetTimeInMinutes();
   if (now >= ldt) return now-ldt; // 正常比较
   return 65535-ldt+now; // 折返比较
}
```

**如何判断是否该回收呢？**

与LRU算法一样也是通过待回收空闲池，只是计算空闲时间idle不同，如下：如下所示：

```c
// LFU计算空闲时间，频次最大值255减去当前频次
unsigned long long estimateObjectIdleTime(robj *o) {
    ...
    } else if (server.maxmemory_policy & MAXMEMORY_FLAG_LFU) {
		/* When we use an LRU policy, we sort the keys by idle time
         * so that we expire keys starting from greater idle time.
         * However when the policy is an LFU one, we have a frequency
         * estimation, and we want to evict keys with lower frequency
         * first. So inside the pool we put objects using the inverted
         * frequency subtracting the actual frequency to the maximum
         * frequency of 255. */    	
    	idle = 255-LFUDecrAndReturn(o);
	}
	...
}

// 当前频次计算，使用对象lru中当前访问频次减去对象已经过的衰减次数
unsigned long LFUDecrAndReturn(robj *o) {
    unsigned long ldt = o->lru >> 8;
    unsigned long counter = o->lru & 255;
    /* 
    * LFUTimeElapsed表示两次访问间时长，lfu_decay_time衰减因子，默认1，单位分钟
    * 两者相除可以理解为经过了几次衰减周期，即衰减了几次
    */    
    unsigned long num_periods = server.lfu_decay_time ? 
        LFUTimeElapsed(ldt) / server.lfu_decay_time : 0;
    if (num_periods)
        // 这个很好理解了，当前频次-已衰减次数，并对负值进行修正
        counter = (num_periods > counter) ? 0 : counter - num_periods;
    return counter;
}
```

通过空闲时间的计算，也可以看出访问频次并不是简单的加一减一，引入了衰减因子的概念lfu_decay_time，可以调整counter的减少速度。对应的还有一个增长因子lfu-log-factor，默认10，越大counter增长越慢。

## 淘汰策略

Redis使用中，如果内存空间用满，将会自动驱逐老的数据。

maxmemory用于配置Redis能使用的最大内存。比如100m。当缓存消耗的内存超过这个数值时, 将触发数据淘汰。该数据配置为0时，表示缓存的数据量没有限制， 即LRU/LFU功能不生效。64位的系统默认值为0，32位的系统默认内存限制为3GB。

maxmemory_policy用于配置淘汰策略，支持策略如下：

- noeviction：如果缓存数据超过了maxmemory限定值，并且客户端正在执行的命令会导致内存分配，则向客户端返回错误响应
- allkeys-lru：对所有的键都采取LRU淘汰
- volatile-lru：仅对设置了过期时间的键采取LRU淘汰
- allkeys-lfu：对所有的键都采取LFU淘汰
- volatile-lfu：仅对设置了过期时间的键采取LFU淘汰
- allkeys-random：随机回收所有的键
- volatile-random：随机回收设置过期时间的键
- volatile-ttl：仅淘汰设置了过期时间的键，淘汰生存时间TTL(Time To Live)更小的键

volatile-lru、volatile-lfu、volatile-random、volatile-ttl这四个淘汰策略使用的不是全量数据，有可能无法淘汰出足够的内存空间。在没有过期键或者没有设置超时时间的键的情况下，这四种策略和noeviction差不多。

一般的经验规则：

- 使用allkeys-lru/allkeys-lfu策略：当预期请求符合一个幂次分布(二八法则等)，比如一部分的子集元素比其它其它元素被访问的更多时，可以选择这个策略
- 使用allkeys-random：循环连续的访问所有的键时，或者预期请求分布平均（所有元素被访问的概率都差不多）
- 使用volatile-ttl：要采取这个策略，缓存对象的TTL值最好有差异

- volatile-lru、volatile-lfu、 volatile-random这三个策略，适用于对常用的键进行持久化，不常用的键通过设置过期时间通过不同的算法进行回收。**但是设置过期时间是需要消耗内存的，可以通过拆分冷热数据到不同的Redis实例，使用allkeys-lru/allkeys-lfu即可**

**如何设置过期时间？**

Redis有四个不同的命令可以用于设置键的生存时间（键可以存在多久）或过期时间（键什么时候会被删除）：（expire.c中）

- EXPIRE＜key＞＜ttl＞命令用于将键key的生存时间设置为**ttl秒**
- PEXPIRE＜key＞＜ttl＞命令用于将键key的生存时间设置为**ttl毫秒**
- EXPIREAT＜key＞＜timestamp＞命令用于将键key的过期时间设置为timestamp所指定的**秒数时间戳**
- PEXPIREAT＜key＞＜timestamp＞命令用于将键key的过期时间设置为timestamp所指定的**毫秒数时间戳**

虽然有多种不同单位和不同形式的设置命令，但实际上EXPIRE、PEXPIRE、EXPIREAT三个命令都是使用PEXPIREAT命令来实现的：无论客户端执行的是以上四个命令中的哪一个，经过转换之后，最终的执行效果都和执行PEXPIREAT命令一样。

![img](https://sheungxin.github.io/notpic/1085463-20180608093450203-758659121.png)

## 虚拟内存

Redis的虚拟内存与OS的虚拟内存不是一码事，但是思路和目的都是相同的。就是暂时把不经常访问的数据从内存交换到磁盘中，从而腾出宝贵的内存空间用于其他需要访问的数据，提高单台Redis Server的内存容量。

由于操作系统的虚拟内存是4k页面为最小单位进行交换，Redis大多数对象远小于4k。这样单个OS页面上可能存在多个Redis对象，热点数据将影响更多的冷数据无法交换到页面。

相比于OS的交换方式，Redis规定同一个页面只能保存一个对象（一个对象可以保存在多个页面中），还将交换到磁盘的对象进行压缩，一般10:1，可以减少IO操作。

**什么时候触发内存交换？**

VM相关参数如下：

- vm-enabled yes：开启VM功能
- vm-swap-file：交换出来的value保存路径，例如：/tmp/redis.swap
- vm-max-memory：Redis使用的最大内存上限，超过上限后Redis开始交换value到磁盘文件中
- vm-page-size：每个页面的大小，单位字节，例如：32
- vm-pages：最多在文件中使用多少页面，交换文件的大小 = vm-page-size * vm-pages，例如：134217728
- vm-max-threads：用于执行value对象换入换出的工作线程数量，0表示使用主线程

在开启VM功能后，只有使用内存超过vm-max-memory上限，才会选择较老且较大的对象进行交换。

对于vm-page-size的设置应该根据实际应用情况，将页面设置为可以容纳大多数对象的大小，避免太大造成磁盘空间浪费，太小造成交换文件出现碎片。注意每个页面在内存中会对应一个bit值记录页面空闲状态。

不常发生换入换出，且主线程由于换入换出造成延迟可接受，推荐使用Blocking VM，即vm-max-threads=0，不启用工作线程，性能会好一些。

# 高可用

## 持久化方案

### RDB

RDB持久化可以手动执行，也可以根据配置定期执行，它的作用是将某个时间点上的数据库状态保存到RDB文件中，RDB文件是一个压缩的二进制文件，通过它可以还原某个时刻数据库的状态。由于RDB文件是保存在硬盘上的，所以即使Redis崩溃或者退出，只要RDB文件存在，就可以用它来恢复还原数据库的状态。

可以通过SAVE或者BGSAVE来生成RDB文件：

- SAVE命令会阻塞Redis进程，直到RDB文件生成完毕，在进程阻塞期间，Redis不能处理任何命令请求，这显然是不合适的

- BGSAVE则是会fork出一个子进程，然后由子进程去负责生成RDB文件，父进程还可以继续处理命令请求，不会阻塞进程

### AOF

AOF是通过保存Redis服务器所执行的写命令来记录数据库状态的，分为以下三个步骤：

- 命令写入：当AOF持久化功能打开时，服务器在执行完一个写命令之后，会以协议格式将被执行的写命令追加到服务器状态的aof_buf缓冲区的末尾
- AOF文件写入WRITE ：根据条件，将aof_buf中缓存命令写入到AOF文件
- AOF文件同步SAVE：根据条件，调用fsync或fdatasync函数，将AOF文件保存到磁盘

**aof_buf什么时候写入文件并同步到磁盘？**

每当服务器常规任务函数被执行、或者事件处理器被执行时， aof.c/flushAppendOnlyFile 函数都会被调用， 这个函数会觉得是否执行AOF文件的写入、同步，保存模式如下：

- AOF_FSYNC_NO ：WRITE 会被执行， 但 SAVE 会被略过。只有Redis被关闭、AOF功能关闭、写缓存刷新才会执行，并堵塞主线程

- AOF_FSYNC_EVERYSEC ：SAVE 原则上每隔一秒钟就会执行一次， 因为 SAVE 操作是由后台子线程调用的， 不会引起服务器主进程阻塞。

  ![img](https://sheungxin.github.io/notpic/graphviz-1b226a6d0f09ed1b61a30d899372834634b96504.svg)

- AOF_FSYNC_ALWAYS ：每次执行完一个命令之后， WRITE 和 SAVE 都会被执行

综合起来，三种 AOF 模式的操作特性可以总结如下：

| 模式               | WRITE 是否阻塞？ | SAVE 是否阻塞？ | 停机时丢失的数据量                                    |
| :----------------- | :--------------- | :-------------- | :---------------------------------------------------- |
| AOF_FSYNC_NO       | 阻塞             | 阻塞            | 操作系统最后一次对 AOF 文件触发 SAVE 操作之后的数据。 |
| AOF_FSYNC_EVERYSEC | 阻塞             | 不阻塞          | 一般情况下不超过 2 秒钟的数据。                       |
| AOF_FSYNC_ALWAYS   | 阻塞             | 阻塞            | 最多只丢失一个命令的数据。                            |

> [Redis AOF原理](https://blog.csdn.net/luolaifa000/article/details/84178289)

## 主从复制

主从复制是最简单的实现高可用的方案，核心就是主从同步。

理解主从同步首先需要理解以下几个概念：

- 服务器运行ID：每个redis服务器开启后会生成运行ID
- 复制偏移量
  - master每执行一次写命令，master偏移量+1
  - slave每执行一次同步过来的master命令，salve偏移量+1
  - master与slave偏移量一致，代表数据一致
  - 全量同步后master与slave偏移量一致
- 复制积压缓冲区
  - 由master维护的固定长度的先进先出队列
  - 由于长度固定，slave偏移量之后的数据可能已经不在缓冲区。此时，只能进行全量同步

**那么Redis是如何进行主从同步的呢？**

首次连接时，进行全量同步。全量同步结束，进行增量同步。断网重连后尝试进行增量同步，若不成功，进行全量同步。详细过程如下：

- slave发送psync命令到master
- master收到psync之后，判断slave传递过来的master id是否与自己一样
  - 若一样，进行偏移量校验
    - 若主从偏移量不一样，则去复制积压缓冲区判断slave的偏移量之后的数据是否存在，如果存在表示slave可以执行部分同步，master会发送断线后的写命令给slave。反之，由于缓冲区有限数据已过期，只能进行**全量同步**
    - 若主从偏移量一致，则不需要进行同步
  - 若不一样，说明master切换了，直接进行**全量同步**
- 同步完成后，master通过**命令传播**的方式进行增量同步。即master每执行一个写命令，就会向slave发送相同的写命令，slave接收并执行收到的写命令

从上述过程，同步可分类为**全量同步、部分同步（缓冲区+偏移量）、增量同步（命令传播）**，其中全量同步过程如下：

- fork一个后台进程，执行bgsave命令生成rdb文件（一般应用在磁盘空间有限但网络状态良好的情况下会启用**无盘复制**，即master直接开启一个socket将rdb文件发送给slave）
- 向所有slave发送快照文件，并在发送期间继续记录被执行的写命令到复制积压缓冲区
- slave收到快照文件后丢弃所有旧数据，载入收到的快照，进行指令重放
- master快照发送完毕后开始向slave发送缓冲区中的写命令
- slave完成对快照的载入，开始接收命令请求，并执行来自master缓冲区的写命令

**Redis如何进行主从超时检测？**

Redis的主从超时检测主要从以下三个方面进行判断：

- 主监测从：slave定期发送replconf ack offset命令到master来报告自己的存活状况
- 从监测主：master定期发送ping命令或者\n命令到slave来报告自己的存活状况
- 正常关闭：eventLoop监测端口关闭的nio事件

## 哨兵模式

哨兵模式具有自动故障转移、集群监控、消息通知等功能，解决了主从架构当master宕机，不能写数据，必须手动切换的问题。

![img](https://sheungxin.github.io/notpic/11320039-3f40b17c0412116c.png)

哨兵可以同时监视多个主从服务器，并且在被监视的master下线时，自动将某个slave提升为master，然后由新的master继续接收命令。

**哨兵模式是如何进行节点通信的？**

当哨兵启动后，每个哨兵会执行以下三种操作，如下：

- 定期的向master、slave和其它哨兵发送PING命令（每秒一次），以便检测对象是否存活。若是对方接收到了PING命令，无故障情况下，会回复PONG命令
- 定期会向（10秒一次）master和slave发送INFO命令，获取主从数据库的最新信息。若是master被标记为主观下线，频率就会变为1秒一次
- 定期向`_sentinel_:hello`频道发送自己的信息，以便其它的哨兵能够订阅获取自己的信息，发送的内容包含「哨兵的ip和端口、运行id、配置版本、master名字、master的ip端口还有master的配置版本」等信息

**如何判断Master下线？**

当哨兵与master通过PING、PONG保持通信，若是某一时刻哨兵发送的PING在指定时间内没有收到回复（down-after-milliseconds配置，默认30s），那么发送PING命令的哨兵就会认为该master**「主观下线」**（`Subjectively Down`）。

因为有可能是哨兵与该master之间的网络问题造成的，而不是master本身的原因。所以哨兵同时会询问其它的哨兵是否也认为该master下线，若是认为该节点下线的哨兵达到一定的数量（sentinel.conf中sentinel monitor <master-name> <ip> <redis-port> <quorum>中quorum配置），就会认为该节点**「客观下线」**（`Objectively Down`）。

若 Master 重新向 Sentinel 的 PING 命令返回有效回复， Master 的主观下线状态就会被移除。若没有足够数量的 Sentinel 同意 Master 已经下线， Master 的客观下线状态就会被移除。 

**客观下线后，如何选择新的Master？**

首先在哨兵中通过Raft算法选择一个老大哨兵，过程如下：

- 发现master下线的哨兵（sentinelA）会向其它的哨兵发送命令进行拉票，要求选择自己为哨兵大佬
- 若是目标哨兵没有选择其它的哨兵，就会选择该哨兵（sentinelA）为大佬
- 若是选择sentinelA的哨兵超过半数（半数原则），该大佬非sentinelA莫属
- 如果有多个哨兵同时竞选，并且可能存在票数一致的情况，就会等待下次的一个随机时间再次发起竞选请求，进行新的一轮投票，直到大佬被选出来

选出大佬哨兵后，大佬哨兵就会对故障进行自动回复，从slave中选出一名slave作为主数据库，选举的规则如下所示：

- 所有的slave中slave-priority优先级最高的会被选中
- 若是优先级相同，会选择偏移量最大的，因为偏移量记录着数据的复制的增量，越大表示数据越完整
- 若是以上两者都相同，选择ID最小的

当选的slave晋升为master，其它的slave会向新的master复制数据，若是down掉的master重新上线，会被当作slave角色运行。

> [Raft协议实战之Redis Sentinel的选举Leader源码解析](https://www.cnblogs.com/myd620/p/7811156.html)

**哨兵模式是否存在缺点？**

哨兵一主多从的模式同样也会遇到写的瓶颈，若是master宕机了，故障恢复的时间比较长，写的业务会受到影响。

哨兵模式还存在难以扩容以及单机存储问题，同时会增加系统的复杂度及运维成本。

> [Redis哨兵（Sentinel）模式](https://www.jianshu.com/p/06ab9daf921d)
>
> [一文把Redis主从复制、哨兵、Cluster三种模式摸透](https://mp.weixin.qq.com/s/sZ0m1IJlth3FIp6jiup8AA)

## Cluster模式

Cluster是真正的集群模式，解决了自动故障转移的同时，支持了数据的分布式存储，实现了在线数据节点的收缩（下线）和扩容（上线）。

**Redis Cluster如何实现数据分片？**

![img](https://sheungxin.github.io/notpic/641.webp)

当客户端请求过来，通过对key进行hash（crc16(key,keylen) & 0x3FFF，0x3FFF=16383，图中错了）计算出key所在的槽，然后再到对应的槽上进行取数据或者存数据，这样就实现了数据的访问更新。

![img](https://sheungxin.github.io/notpic/642.webp)

**通过crc16(key,keylen) & 0x3FFF可以计算key所在的槽，但是槽所在节点如何确定呢？**

![img](https://sheungxin.github.io/notpic/643.webp)

集群建立后，每个节点负责一部分槽位slots。在设计客户端时，连接任意一个节点，拿到所有槽位和节点的映射关系并本地化。客户端发起请求时，通过本地映射找出key所在的机器。

但是Redis Cluster支持在线扩容和收缩。当请求到某一个节点时，新节点加入或者节点收缩，部分槽位可能正在迁移或者已经迁移，二进制数组对应下标位已经不是1，这时应该如何处理？

Redis在底层使用了**两个长度为16384的数组**，其中一个是一个二进制数组myslots，使用0和1表示当前实例是否存在该槽位（1表示存在）。这样，当槽位发生迁移，二进制数组同步更新下标值为0。

接下来如何处理呢？当然是找出迁移后槽位对应的节点信息，这时候就需要用到第二个数组clusterNode，存储节点的元数据信息，节点变化后会及时更新。找到对应新节点信息后，就会向客户端发送一个MOVED(已迁移)/ASK(迁移中)重定向请求，并返回客户端迁移目标节点的IP和端口。

客户端收到重定向请求后，会更新本地映射，重定向新的数据节点。需要注意，以上重定向过程可能经过多次，如果超过5次，那么就报错JedisClusterMaxRedirectionException。

**Redis Cluster如何实现节点通信？**

使用Gossip协议，每个节点都与剩余的N-1个节点建立连接，即任意两个节点之间都有两个网络连接。使用meet、ping、pong消息进行通信，如下图：

![img](https://sheungxin.github.io/notpic/640.webp)

- 节点A收到客户端的cluster meet命令
- A根据收到的IP地址和端口号，向B发送一条meet消息
- 节点B收到meet消息返回pong
- A知道B收到了meet消息，返回一条ping消息，握手成功
- 最后，节点A将会通过gossip协议把节点B的信息传播给集群中的其他节点，其他节点也将和B进行握手

**Redis Cluster如何判断节点宕机？**

和哨兵模式一样，存在主观宕机pfail和客观宕机fail。

- 在 cluster-node-timeout 内，某个节点一直没有返回 pong，那么就被认为 pfail
- 如果一个节点认为某个节点 pfail 了，那么会在 gossip ping 消息中，ping 给其他节点，如果超过半数的节点都认为 pfail 了，那么就会变成 fail

**节点宕机后，Redis Cluster如何进行选主？**

例如slave A首先发现自己master下线，就会试图发起故障转移，如下所示：

- 首先将自己的currrentEpoch加1，并广播failover request信息给其他的master节点（已投票节点没资格发起选举）
- 首个广播出去的currentEpoch是集群中最大的，大家很可能都投票给salve A（首个广播不一定首个到达，其他节点可能已投票给其他节点），并更新为自己的currentEpoch
- slave A收到的failover_auth_ack超过半数，成为新的master，广播通知其他集群节点。此时，新的master会增加自己的[configEpoch](https://blog.csdn.net/chen_kkw/article/details/82724330)，强制其他节点更新相关 slots 的负责节点为自己

不是每个节点都可以成为master，会检查每个 slave node 与 master node 断开连接的时间，如果超过了 cluster-node-timeout * cluster-slave-validity-factor，那么就没有资格切换成 master。

多个slave如何快速选择出最佳节点切换为master？

不同的slave节点感知master fail时间可能存在差异，并随机延迟发起选举，延迟公式如下：

**DELAY = 500ms + random(0 ~ 500ms) + SLAVE_RANK * 1000ms**

SLAVE_RANK表示此slave已经从master复制数据的总量的rank，越小代表已复制的数据越新，理论上持有最新数据的slave将会首先发起选举。发起选举存在时间差，也更容易过半选举成功。

**Redis Cluster是否存在缺点？**

- 数据一致性问题，缓存的普遍现象，大多使用最终一致性
- 一个集群最少6个节点，3个master（满足过半选举）、3个slave（满足高可用，每个master必须对应一个slave节点）
- slave只是冷备，并不能缓解master的读压力（官方默认设置的是不分担读请求的，只作备份和故障转移用。当有请求读向从节点时，会被重定向对应的主节点来处理。可手动执行命令readonly后读取从节点）

# 事件循环

- [Redis 中的事件循环](https://www.cnblogs.com/shijingxiang/articles/13112275.html)

# 常见问题

## Redis为什么快呢？

见特性中高性能

## 那为什么Redis6.0之后又改用多线程呢?

redis使用多线程并非是完全摒弃单线程，redis还是使用单线程模型来处理客户端的请求，只是使用多线程来处理数据的读写和协议解析，**执行命令还是使用单线程**。

这样做的目的是因为redis的性能瓶颈在于网络IO而非CPU，使用多线程能提升IO读写的效率，从而整体提高redis的性能。

## 什么是热key吗？热key问题怎么解决？

所谓热key问题就是，突然有几十万的请求去访问redis上的某个特定key，那么这样会造成流量过于集中，达到物理网卡上限，从而导致这台redis的服务器宕机引发雪崩。

针对热key的解决方案：

- 提前把热key打散到不同的服务器，降低压力
- 加入二级缓存，提前加载热key数据到内存中，如果redis宕机，走内存查询

## 什么是缓存雪崩、缓存击穿、缓存穿透？

**缓存雪崩**

当某一时刻发生大规模的缓存失效的情况，比如缓存服务宕机或者大量热点数据过期，会有大量的请求进来直接打到DB上，这样可能导致整个系统的崩溃，称为雪崩。

解决方案：

- 事前：
  - Redis 高可用，主从+哨兵，Redis cluster，避免全盘崩溃
  - 设置随机过期时间，防止同一时间大量数据过期现象发生
  - 热点数据永不过期
- 事中：本地 ehcache 缓存 + hystrix 限流&降级，避免 MySQL 被打死
- 事后：Redis 持久化，一旦重启，自动从磁盘上加载数据，快速恢复缓存数据

**缓存击穿**

缓存击穿的概念就是单个key并发访问过高，过期时导致所有请求直接打到db上，这个和热key的问题比较类似，只是说的点在于过期导致请求全部打到DB上而已。

解决方案：

- 互斥锁：加锁更新，比如请求查询A，发现缓存中没有，对A这个key加锁，同时去数据库查询数据，写入缓存，再返回给用户，这样后面的请求就可以从缓存中拿到数据了
- 通过异步的方式不断的刷新过期时间，防止此类现象
- 设置热点数据永不过期

**缓存穿透**

缓存穿透是指查询不存在缓存中的数据，每次请求都会打到DB，就像缓存不存在一样。

解决方案：

- 布隆过滤器

  布隆过滤器的原理是在你存入数据的时候，会通过散列函数将它映射为一个位数组中的K个点，同时把他们置为1。这样当用户再次来查询A，而A在布隆过滤器值为0，直接返回，就不会产生击穿请求打到DB了。

  上文中有提到布隆过滤器存在误判问题，对于过滤器值为1的情况，只是有可能存在，需要再查询缓存/数据库。为了降低误判率，理论上通过增大数组长度即可。Redis提供的官方插件中提供了bf.reserve设置准确度，根据实际业务场景设置即可。

- 缓存空值

  数据库没查到的数据写一个空值到缓存，并设置过期时间（无法解决不同无效key问题，可配合相关安全策略解决，例如：限制相同IP访问次数、参数过滤等）

## 缓存一致性问题

**先更新DB还是先操作缓存？**

不管先更新DB还是先操作缓存，都存在数据一致性问题，分析如下：

- 如果先更新缓存成功，后更新DB失败，后续请求会读取到缓存中未更新到DB中的数据，数据读取错误
- 如果先淘汰缓存成功，后更新DB成功，如果在更新DB完成之前发起一起新的请求，缓存还是会加载旧的数据，导致DB更新之后两者数据不一致
- 如果先更新DB，后更新/淘汰缓存失败，同样存在读取旧数据的问题。就算缓存操作成功，更新DB之后，操作缓存之前的时间段，也会出现读取旧数据的情况

根据以上分析，单纯的先更新DB还是先操作缓存，并不能解决缓存一致性问题。但可以确定，先更新缓存是不可行的，会读取到未更新数据的问题。

**如何保证更新DB和操作缓存的数据一致性？**

更新DB和操作缓存是非原子性的，一般使用最终一致性实现。例如，使用消息队列的消息保证机制实现最终一致性，先更新DB数据，然后发送操作缓存的消息到消息队列，客户端重试+报警机制达到数据的最终一致性。

**更新缓存还是淘汰缓存？**

不论是更新缓存，还是淘汰缓存，都有可能存在缓存不一致的情况，更新缓存相对可能性更大，分析如下：

- 先更新DB，后更新缓存
  - 如果更新缓存操作依赖复杂的计算或者DB交互查询，即耗时较长，写多读少的场景不建议（lazy思想，频繁更新可能并不会被使用）
  - 并发写问题，请求A、B先后对同一条数据进行DB操作，然后进行缓存更新，请求B对应的更新缓存有可能先于请求A发生，缓存旧数据造成数据不一致
  - 采用MQ重试+报警机制，更新DB和更新缓存之间可能存在断层，并不一定能保证缓存更新成功
- 先更新DB，后淘汰缓存
  - 采用MQ重试+报警机制，更新DB和淘汰缓存之间可能存在断层，并不一定能保证缓存淘汰成功

通过上述分析，明显淘汰缓存的方案较好，面临的问题更少。实际业务中，场景可能更为复杂，还需要考虑读写分离，主从同步延迟导致缓存不一致的情况。

**参考方案**

- 方案1：读写串行化

  更新操作通过路由分发到内部队列。读取时，如果缓存为空，也加入队列（和更新相同队列），过滤连续的读请求加入队列，读超时，直接读数据库，并在队列加入强制更新缓存请求。

  > [数据库与缓存双写不一致问题分析与解决方案设计](https://blog.csdn.net/sun_qiangwei/article/details/80095980)

- 方案2：异步补偿

  先淘汰缓存+更新DB+异步更新缓存（binlog+MQ）+锁定标识（已锁定数据读请求走DB）+定时任务（解决主从延迟）

  ![img](https://sheungxin.github.io/notpic/db-and-cache-04-01.jpg)

  **缺点很明显，依赖过多，复杂度比较高**

  > [缓存与数据库一致性系列](https://blog.kido.site/2018/11/24/db-and-cache-preface/)

## 脑裂问题

**什么是脑裂？**

master脱离正常网络，集群重新选举了新的master节点。由于原来的master还正常运行，且部分client未及时切换到新的master，还继续向旧的master发送数据。当旧的master网络恢复，会被作为slave挂到新的master下，自己清空数据，重新从master复制数据，造成数据丢失。

**如何解决脑裂数据丢失问题？**

同步延迟太长拒绝客户端的写请求，可通过以下参数配置：

- min-slaves-to-write=1：至少有一个slave在数据同步，新版参数min-replicas-to-write
- min-slaves-max-lag=10：数据复制和同步不能超过10秒，新版参数min-replicas-max-lag

# 案例分析

- [秒杀实战](https://www.cnblogs.com/chenyanbin/p/13587508.html)
- [秒杀商品超卖事故：Redis分布式锁请慎用！](https://mp.weixin.qq.com/s/75BqVaRL8NohtH7CsibTWg)
- [Redis如何助力高并发秒杀系统](https://mp.weixin.qq.com/s/WlvwtdYgjfBqjUHkrBSrIw)