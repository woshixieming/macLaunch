# MacLaunch

MacLaunch 是一个使用 SwiftUI 构建的轻量级 macOS 启动台替代应用，适合在新版 macOS 中恢复类似“启动台”的应用浏览和快速启动体验。

[English README](./README.md)

## 功能

- 全局快捷键显示和隐藏启动台
- 固定应用，并支持拖拽排序
- 可开关的最近使用应用区域
- 应用库分页，支持自定义行数和列数
- 鼠标滚轮翻页，并支持独立灵敏度设置
- 键盘方向键导航和快捷启动
- 点击空白区域或按 `Esc` 关闭
- 新增或删除应用后自动刷新应用列表

## 使用方式

- 按设置中的全局快捷键打开启动台。
- 点击应用图标即可启动应用。
- 按 `Esc` 或点击背景区域关闭启动台。
- 拖拽应用可以调整固定区或应用库排序。
- 从菜单栏打开设置窗口，可调整快捷键、最近使用、布局和滚轮翻页行为。

## 构建与打包

构建 Release 版 `.app`：

```bash
./scripts/package_app.sh
```

构建 `.dmg` 安装镜像：

```bash
./scripts/package_dmg.sh
```

执行完整本地发布流程：

```bash
./scripts/release.sh
```

发布到 GitHub Release：

```bash
./scripts/setup_github_repo.sh
./scripts/publish_github_release.sh
```

构建产物会输出到 `dist/` 目录。

## 仓库说明

- 构建产物通过 `.gitignore` 忽略。
- 发布产物位于 `dist/`。
- `VERSION` 控制发布版本号和产物文件名。
- `scripts/setup_github_repo.sh` 用于检查 Git 和 GitHub CLI 配置。
- `scripts/publish_github_release.sh` 用于推送 tag 并创建 GitHub Release。
- 项目使用 GPLv3 或更高版本协议。
- 发布细节请参考 [`RELEASE.md`](./RELEASE.md)。

## 许可证

本项目基于 GNU General Public License v3.0 or later 发布。
完整协议文本请查看 [`LICENSE`](./LICENSE)。
