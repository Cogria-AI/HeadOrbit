<p align="center">
  <img src="docs/banner.png" alt="HeadOrbit" width="100%">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="https://headorbit.com">headorbit.com</a>
</p>

<p align="center">
  <img src="docs/icon.png" alt="" width="128">
</p>

# HeadOrbit

一个很小的 macOS 菜单栏应用。它读取 AirPods 的头部运动数据，把「你的头朝哪儿」变成屏幕上一点点有用的小事。

转头不看屏幕，屏幕就模糊。弯腰塌下去、下巴抬起来，它提醒你坐直。目前就这两件事。

> **状态：实验性质，做着玩的。**
> 创意灵感来自 [@bryllim_ 的这条推文](https://x.com/bryllim_/status/2099049704822907277)。这是一个周末项目级别的小工具，不是产品，边角会有点糙。

## 功能

- **看向别处时模糊屏幕。** 头向左或向右转过设定角度，整个屏幕柔和地模糊；转回来即恢复。
- **坐姿提醒。** 坐直时校准一次。之后弯腰塌下去、头仰起来继续看屏幕时，屏幕模糊并显示提醒，坐直即恢复。按 `Esc` 解除并暂停一分钟。
- **实时头部角度**显示在菜单里，看得到耳机看到的东西。
- **一键校准。** 点下去那一刻的姿态就是「正前方」。
- **菜单栏状态图标。** 没连耳机时是空心的，耳机在传数据时是实心的。
- **中文 / English / 日本語**，跟随系统语言，也可以在菜单里手动切换。
- **亮色 / 暗色 / 跟随系统**三种面板外观。

所有数据都留在你的 Mac 上。不联网，不录屏，不需要账号。

## 要求

- macOS 14 Sonoma 或更新
- 支持头部追踪的 AirPods 或 Beats，例如 AirPods Pro（任意代）、AirPods 3 / 4、AirPods Max、Beats Fit Pro、Powerbeats Pro 2
- 耳机必须连接到**这台 Mac**。如果它自动切到了 iPhone，Mac 就收不到运动数据。
- 戴一只或两只都可以。

## 安装

### 方式一：直接下载

到 [Releases](https://github.com/Cogria-AI/HeadOrbit/releases) 页面下载最新的 `HeadOrbit-vX.Y.Z.dmg`，打开后把 `HeadOrbit` 拖进「应用程序」文件夹。

这个应用没有经过 Apple 公证，第一次打开时 macOS 会提示无法验证开发者。**右键点击应用 → 打开 → 打开**即可，或者执行一次：

```bash
xattr -d com.apple.quarantine /Applications/HeadOrbit.app
```

### 方式二：源码编译

```bash
brew install xcodegen          # 只需一次
git clone https://github.com/Cogria-AI/HeadOrbit.git
cd HeadOrbit
./build.sh
open build/Build/Products/Debug/HeadOrbit.app
```

需要 Xcode 15 或更新。

### 第一次启动

macOS 会询问**运动与健身**权限，允许即可，这是 HeadOrbit 唯一需要的权限。HeadOrbit 只住在菜单栏里，没有 Dock 图标，也没有窗口。

## 使用

1. 戴上 AirPods，确认它连接的是这台 Mac。
2. 点菜单栏里的 HeadOrbit 图标。顶部状态应显示**正在追踪（左耳）**或**正在追踪（右耳）**，告诉你是哪只耳机在提供数据。
3. 坐直、平视屏幕，点**以当前姿态为正前方**。之后所有角度都相对这个姿态计算，换了椅子或者换了心情就再点一次。
4. 打开你想要的功能，调一调滑块。

<p align="center">
  <img src="docs/panel-zh.png" alt="HeadOrbit 菜单" width="320">
</p>

菜单里每个功能旁边都有一个小 ⓘ 图标，鼠标悬停会显示一句话说明。

## 配置

### 看向别处时模糊屏幕

| 设置 | 作用 | 默认 |
|---|---|---|
| 触发角度 | 头向左或向右转多少度算「没在看屏幕」 | 35° |
| 转开多久后触发 | 转开后要持续多久才触发，避免随便瞟一眼就模糊 | 0.6 秒 |
| 压暗程度 | 在模糊之上再压一层暗色 | 0.15 |

### 坐姿提醒

| 设置 | 作用 | 默认 |
|---|---|---|
| 触发角度 | 头部仰角高于这个值就提醒（抬头为正，相对校准姿态）。校准时已经有点塌的话，可以设成 0 或负数 | +15° |
| 持续多久后提醒 | 坏姿势要持续多久才提醒。弯腰是慢慢发生的，所以这里以秒计 | 5 秒 |

坐姿提醒默认关闭，因为它只有在校准之后才有意义。提醒显示时按 `Esc`，或者在菜单里点**解除并暂停 1 分钟**。

### 语言和外观

都在菜单底部。语言默认：系统是中文就显示中文，日文就显示日文，否则英文。

## 常见问题

**戴着 AirPods 却显示「未检测到支持头部追踪的耳机」**
- 确认耳机连的是 Mac 而不是 iPhone（控制中心 → 声音）。
- 摘下来再戴上。只有戴着的时候才会传运动数据。
- 确认型号支持头部追踪（见「要求」）。

**运动与健身权限被拒绝**
- 系统设置 → 隐私与安全性 → 运动与健身 → 打开 HeadOrbit。
- 如果你自己重新编译了应用，macOS 可能会再问一次，本地签名的构建就是这样。

**模糊效果看起来像一层平的深色，不像模糊**
- HeadOrbit 用的是 WindowServer 里一个 Apple 没有公开的模糊接口。如果未来的 macOS 把它去掉了，遮罩会退化成只压暗。

## 以后可能做的

- 低头看手机 → 暂停正在播放的媒体
- 快速甩头 → 切歌或切换桌面
- 离开屏幕一段时间 → 锁屏
- 转头看向另一块显示器 → 把焦点切过去

如果你做了其中任何一个，非常欢迎提 Pull Request。

## 许可

[MIT](LICENSE) © 2026 [Cogria-AI](https://github.com/Cogria-AI)

作者 [@rfboen](https://x.com/rfboen)。
