# daka(打卡)

这是一个可以用来打卡的服务器. 

客户端需要在设定的时间间隔内, 重复的的通过客户端向服务器发送一个请求打卡.

服务端则根据打卡记录, 分析用户的行为, 显示, 客户什么时候在线(online), 什么时候离线(offline)

## 服务端安装

下载最新的版本的 [release bianry](https://github.com/crystal-china/daka/releases), 拷贝到一台 Linux 服务器上直接执行即可, 

默认监听在 0.0.0.0:3000, 也可以手动指定监听地址和端口:

```sh
bin/daka -b 127.0.0.1 -p 3001
```

你可以通过环境变量 `DAKAPWD` 设定新的密码, 默认是 1234567

```sh
DAKAPWD=newpass bin/daka -b 127.0.0.1 -p 3001
```


默认要求打卡时间为 `1 分钟`, 通过 `DAKAINERVAL` 设定要求的打卡间隔.

服务器允许 2 分钟时间的冗余, 即: 假如服务器设定要求打卡时间间隔为 10 分钟, 最长 12 分钟都被视为成功打卡.

可以通过访问 /admin 输入密码进入打卡记录页面.

你也可以直接通过命令行来查看打卡记录, 将会以表格的形式输出到终端.

 ```sh
 $: xhs -b -a user:1234567 https://your_server/admin
 ```

## 客户端安装

客户端请使用 [xh](https://github.com/ducaale/xh)

以 Linux 下使用为例:

```sh
$: xhs -a user:1234567 https://your_server/daka hostname=${HOSTNAME} --ignore-stdin
```

hostname 是必须的, 用来区分不同用户.

Linux 系统可以通过 systemd, 实现定时打卡.

### 在 Linux 定时打卡

#### 创建 service 以及 timer 文件.

 ~/.config/systemd/user/daka.service

 ```systemd
 [Unit]
 Description=daka

 [Service]
 Type=oneshot
 ExecStart=/usr/local/bin/daka
 ```

 ~/.config/systemd/user/daka.service

 ```systemd
 [Unit]
 Description=Run daka periodically

 [Timer]
 # DayOfWeek Year-Month-Day Hour:Minute:Second
 # more detail, see man 5 systemd.timer man 7 systemd.time

 OnCalendar=*-*-* *:00/1:00
 RandomizedDelaySec=20
 # Persistent=true

 [Install]
 WantedBy=timers.target
 ```
 
 #### 创建打卡脚本:
 
```sh
 #!/usr/bin/env sh

set -eu

/usr/bin/xhs https://your_server/daka hostname=${HOSTNAME} --ignore-stdin --timeout=10
``` 

#### 启动 timer systemd 服务

```sh
$: systemctl --user enable daka.timer --now
```

### 在 Windows 定时打卡

#### 编写如下bat批处理脚本，用来每隔一分钟执行一下命令：

`.\xh.exe https://your_server/daka hostname=myhostname --ignore-stdin --timeout=5`

其中`/b`用来静默执行，作用就是执行`xh.exe`的时候不在弹出命令提示符窗口

> 使用时请替换下面的路径（`xh.exe`）

C:\Users\zw963\daka.bat

```bat
@echo off
chcp 65001 >nul
:loop
start /b "" "C:\Users\zw963\xh.exe" "https://your_server/daka" hostname=myhostname --ignore-stdin --timeout=5 >nul 2>&1
@rem echo 打卡时间：%date% %time% > con:
timeout /t 60 /nobreak >nul
goto loop
```

#### 现在编写一个`vbs`脚本，用来执行上面的`bat`

至于为什么要用`vbs`，是因为用`vbs`可以在执行上述`bat`的时候也不弹出命令提示符。

`vbs`命令如下：

> 使用时请替换下面的路径（`daka.bat`）

C:\Users\zw963\daka.vbs

```vbscript
Set ws = CreateObject("WScript.Shell")
ws.Run "C:\Users\zw963\daka.bat", 0, False
```

### 将`VBS`脚本设置为开机自启（会在用户登录时自动运行）

运行如下`reg`文件

> 使用时请替换下面的路径（`daka.vbs`）

```
@echo off
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Run_daka_VBS" /t REG_SZ /d "C:\Users\zw963\daka.vbs" /f
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/zw963/daka/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Billy.Zheng](https://github.com/zw963) - creator and maintainer
