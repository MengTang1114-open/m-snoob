# 给 Agent：怎么帮用户装雪噗噗（Snoob）

雪噗噗是 macOS 菜单栏 App（Swift，Swift Package Manager），基于 Snowhush（MIT）。要求 macOS 14 以上。没有现成的安装包，要在用户的 Mac 上从源码编译。

## 安装步骤

1. 确认是 macOS 14 以上：`sw_vers -productVersion`。更低的版本跑不了，直接告诉用户。
2. 确认有 Swift：`swift --version`（要 5.9 以上）。没有就让用户跑 `xcode-select --install`，装完再继续。这一步会弹系统窗口，要用户自己点。
3. 拿代码：`git clone https://github.com/MengTang1114-open/m-snoob.git`，然后 `cd m-snoob`。
4. 编译：`./build.sh`，产物是 `build/Snoob.app`。第一次要下载依赖（Sparkle），可能要一两分钟。只有命令行工具、没有完整 Xcode 时，脚本会自动只编当前架构，这是正常的。
5. 装好并打开：
   ```bash
   rm -rf /Applications/Snoob.app
   cp -R build/Snoob.app /Applications/
   open /Applications/Snoob.app
   ```
   本地编译的 App 用的是临时签名，不会被 Gatekeeper 拦。
6. 告诉用户：
   - 它在菜单栏（雪花图标），程序坞里没有它；屏幕右下角有一只悬浮的小雪噗噗，点它打开设置。
   - 动一下键盘鼠标开始计时，满 25 分钟它会从窗口顶上冒出来举牌，点它一下就算休息了。时间可以在面板「休息提醒」里改。
   - 如果点雪噗噗时所有窗口被推开：系统设置 → 桌面与程序坞 → 「点按墙纸以显示桌面」改成「仅在台前调度中」。

## 更新

```bash
cd m-snoob && git pull && ./build.sh
osascript -e 'quit app "Snoob"'; rm -rf /Applications/Snoob.app; cp -R build/Snoob.app /Applications/; open /Applications/Snoob.app
```

## 卸载

先在面板里点「退出雪噗噗」，然后：

```bash
rm -rf /Applications/Snoob.app
defaults delete com.mengtang1114.snoob   # 清掉设置和计时记录，可选
```

## 改代码

- 代码在 `Sources/Snowhush/`。Swift 目标名沿用上游的 Snowhush，产物在 `build.sh` 里改名成 Snoob。
- 休息提醒相关：`RestClock.swift`（计时）、`Reminder.swift`（举牌和位置）、`RestPanel.swift`（悬浮雪噗噗和面板）、`GhostPortrait.swift`（悬浮雪噗噗和图标的形象）。
- 设置都在 `Preferences.swift`，存在 `UserDefaults`，bundle id `com.mengtang1114.snoob`。
- 界面文字是中文，改的时候保持口吻简单、短。
- 署名：README、关于页、面板底部保留「基于 Snowhush by mbezruchko，MIT」，LICENSE 里上游的版权行不能删。
