[scrapyd和scrapydweb使用详细教程](https://www.cnblogs.com/gambler/p/12059541.html)



(scrapy) E:\workspaces\idea\sbda\carumkttags>conda install scrapy
Collecting package metadata (repodata.json): failed

UnavailableInvalidChannel: The channel is not accessible or is invalid.
  channel name: simple
  channel url: http://pypi.doubanio.com/simple
  error code: 404

You will need to adjust your conda configuration to proceed.
Use `conda config --show channels` to view your configuration's current state,
and use `conda config --show-sources` to view config file locations.



(scrapy) E:\workspaces\idea\sbda\carumkttags>conda config --show channels
channels:
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/free/
  - http://pypi.doubanio.com/simple/
  - https://pypi.douban.com/simple
  - https://pypi.tuna.tsinghua.edu.cn/simple/
  - defaults

(scrapy) E:\workspaces\idea\sbda\carumkttags>conda config --show-sources
==> C:\Users\user\.condarc <==
channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/free/
  - http://pypi.doubanio.com/simple/
  - https://pypi.tuna.tsinghua.edu.cn/simple/
  - defaults
show_channel_urls: True



channels:

  - https://repo.continuum.io/pkgs/main/win-64/
  - https://repo.continuum.io/pkgs/free/win-64/
  - http://mirrors.aliyun.com/pypi/simple/
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/free/
  - http://pypi.doubanio.com/simple/
  - https://pypi.douban.com/simple/
  - https://pypi.tuna.tsinghua.edu.cn/simple/
  - defaults
show_channel_urls: true

**重置安装通道为默认值解决**

```text
conda config --remove-key channels
```

[conda安装gurobi：UnavailableInvalidChannel](https://zhuanlan.zhihu.com/p/102122665)



[scrapyd 部署爬虫项目](https://blog.csdn.net/LH_python/article/details/79658855)

使用scrapy做爬虫遇到的一些坑：调试成功但是没有办法输出想要的结果（request的回调函数不执行）（url去重）dont_filter=True
