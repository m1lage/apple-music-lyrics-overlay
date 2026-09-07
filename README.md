# Apple Music 歌词悬浮窗

一个原生 macOS 悬浮窗小工具：实时显示 Apple Music 正在播放歌曲的同步歌词（可选中文翻译），常驻桌面、优先级高于普通窗口、切换到别的 App 或桌面空间都不会被挡住或打断。

## 功能

- **真悬浮**：`NSPanel`，`level = .floating`，`collectionBehavior` 加了 `canJoinAllSpaces` + `fullScreenAuxiliary`，所以在所有桌面空间、包括全屏 App 之上都能看到，不抢焦点、不进 Dock。
- **歌词来源**：Apple Music 官方没有开放歌词接口，改为按曲名 + 艺人 + 专辑 + 时长去 [lrclib.net](https://lrclib.net)（免费开源歌词库）匹配同步歌词（LRC 格式）。如果只有无时间轴的纯文本歌词（中文歌常见），会退化成按歌曲时长均匀估算时间点，保证至少有得看。
- **中文翻译**：非中文歌词行用 macOS 系统自带的 Translation 框架做离线翻译，源语言锁定英语（避免短促语气词识别不准时系统弹窗问你选语言）。
- **两种显示状态**：
  - 默认收起成一个小胶囊：圆点 + 当前歌词 + 翻译，常驻显示不需要悬停；
  - 鼠标悬停展开：额外显示歌曲名和下一句歌词。
- **长歌词滚动**：一行放不下时左右来回滚动显示完整内容，而不是截断加省略号。
- **菜单栏图标**：显示/隐藏、开启点击穿透（穿透后鼠标点击会直接打到悬浮窗背后的内容）。
- 悬浮窗可拖动；展开/收起或内容变化导致的尺寸变化，始终保持窗口自己的右上角位置不动。

## 依赖 / 系统要求

- macOS 15 (Sequoia) 及以上 —— 用到了 Translation 框架
- 已安装 Apple Music.app，并且有正在播放/暂停的曲目
- 首次运行会弹一次系统权限对话框，请求控制 Music.app（用于读取当前播放信息），点允许即可，只需要一次

## 构建 & 运行

```bash
./build_app.sh
open "Apple Music 歌词悬浮窗.app"
```

`build_app.sh` 会用 `swift build -c release` 编译，然后打包成一个可直接双击运行的 `.app`（ad-hoc 签名）。

## 项目结构

```
Sources/LyricsOverlay/
  main.swift            入口，创建 NSApplication
  AppDelegate.swift      串联 MusicController / LyricsService / 视图模型，菜单栏
  MusicController.swift  轮询 Apple Music（AppleScript）
  LyricsService.swift    lrclib.net 歌词请求 + LRC 解析 + 纯文本兜底
  LyricsViewModel.swift  当前行/下一行状态
  LyricsOverlayView.swift 胶囊 / 展开面板两种 SwiftUI 视图
  MarqueeText.swift      超长单行文字的滚动效果
  OverlayWindow.swift    悬浮 NSPanel，尺寸变化时锁住右上角
```

## 开发笔记

这个工具是几轮来回打磨出来的，记录几个踩过的坑：

- **AppleScript 变量名 `st` 会导致语法错误**：`set st to player state as string` 编译不过，换成 `stateStr` 才行，原因不明，怀疑是保留标识符冲突。
- **字段分隔符用控制字符会在 NSAppleScript 里丢失**：一开始用 `\u{1F}`（unit separator）拼接返回字段，结果这个字符在 AppleScript 源码里没能正常保留下来，换成普通的 `<|>` 字符串就正常了。
- **中文歌"找不到歌词"**：lrclib.net 上很多中文歌只贡献了无时间轴的纯文本歌词，原本的实现只认 `syncedLyrics`，直接丢弃了这些结果。加了纯文本兜底（按时长均匀估算时间戳）之后就能显示了。
- **SwiftUI `.frame(maxWidth:)` + `.fixedSize()` 组合会让视图始终撑到最大宽度**，而不是按内容自适应收缩——这是个常见坑，解决方式是只在最内层的 `Text` 上加宽度上限，外层容器不加 `maxWidth` 只加 `fixedSize`，才能让短文本正常收缩、长文本正常触发滚动/截断。
- **Translation 框架 `source: nil`（自动检测）在遇到 hiphop 里的短促语气词时会弹系统对话框**，让用户手动选语言，体验很差。固定传 `source: .init(identifier: "en")` 后就不会再触发这个弹窗（因为能走到翻译这一步的文本已经排除了中文）。

## 已知局限

- lrclib.net 覆盖率有限，比较冷门或很新的歌可能完全搜不到歌词。
- 纯文本兜底的时间轴只是估算，不是歌曲真实的逐句时间戳。
- 翻译源语言固定为英语，其他语言（日语、韩语等）暂不支持翻译。
