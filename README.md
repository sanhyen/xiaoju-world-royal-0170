# 小鞠世界：皇家精工版

小鞠世界是基于 Godot 的非官方同人探索游戏。本仓库记录 2026 年 11 月 8 日的皇家精工工程，包括仙岛、道路、浅溪、乘船、天空游览与地图相关的增量内容。

## 源码与资源范围

仓库包含当前工程中的 GDScript、着色器、场景、导入资源和素材。`scripts/renewal/` 是可编辑的增量模块。原版部分逻辑只有 162 个编译后的 `.gdc` 文件，现有工程不包含这些文件对应的完整源码。因此，仓库不能视为整个游戏完整源码的发布。

部分原始资源只以 Godot 导入后的格式存在，主场景使用 `.tscn.remap` 指向 `.godot/exported/` 中的二进制场景。`.godot/imported/` 和 `.godot/exported/` 在本仓库中属于工程所需资源，请勿按普通缓存统一删除。

仓库不包含玩家存档、`UserMedia` 用户目录、Windows 可执行程序或本机的历史测试数据。项目内原有的媒体资源按项目提供者确认的公开范围保留。

## 获取工程

需要 Git 和 Git LFS。安装 Git LFS 后克隆：

```sh
git lfs install
git clone https://github.com/sanhyen/xiaoju-world-royal-0170.git
cd xiaoju-world-royal-0170
git lfs pull
```

工程使用 Godot 4.7.2 和 Mobile 渲染器。项目入口为 `project.godot`。Windows 导出环境需要自行准备。

`scripts/renewal/qa/build_pack.gd` 是用于保留原版编译脚本和导入资源的兼容打包脚本。普通导出可能遗漏原版二进制场景或映射资源。执行打包前应先确认 Godot 版本，并确保目标目录可写。

在 Windows PowerShell 中，可以从仓库根目录运行：

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force build | Out-Null
& $godot --headless --path . --script res://scripts/renewal/qa/build_pack.gd -- build/XiaojuWorld.pck
```

请将 `$godot` 改为本机引擎路径。此命令生成 PCK；仓库不附带 Windows 游戏启动程序。

## 已知边界

2026 年 11 月 8 日的正式包曾通过道路支撑、碰撞、地图、乘船、存档兼容和性能专项检查。自动化检查覆盖有限；画面风格和操作手感仍需玩家确认。

发布前，从工程快照重新打包，并与当时的正式包逐项比较。正式包的 4,555 个资源条目均存在且内容一致。使用独立目录、隔离存档和本机游戏启动程序运行了 40 项移动检查，结果全部通过。

## 许可证

代码采用 [MIT 许可证](LICENSE)。字体和基础环境音保留各自许可，见 [第三方许可](LICENSES/THIRD_PARTY_NOTICES.md)。
