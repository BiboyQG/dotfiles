# 我的 dotfiles

[English](README.md) · 简体中文

适用于 **Apple Silicon Mac** 的个人配置，不支持 Intel Mac。

包含 Zsh、Kitty、tmux、Neovim，以及 AeroSpace 窗口管理、SketchyBar、Yazi 和 VS Code 配置。[`home/`](home/) 中的文件由 GNU Stow 链接到用户目录，依赖由 [`Brewfile`](Brewfile) 和 [`setup.sh`](setup.sh) 管理。

## 快速开始

```sh
xcode-select --install   # 未安装 Command Line Tools 时运行一次
git clone git@github.com:BiboyQG/dotfiles.git
cd dotfiles
zsh setup.sh --skip-system-defaults
```

安装脚本会安装或更新工具、部署配置链接，并重启或重载 OpenUsage、AeroSpace 和 SketchyBar。若还要应用 macOS 系统偏好和 NVRAM 设置，运行 `zsh setup.sh`。

## 检查

```sh
zsh check.sh          # 确定性检查和隔离的部署模拟
zsh check.sh --live   # 额外检查已安装工具及本机状态
```

## 文档

- [安装与维护（英文）](docs/setup.md)：安装细节、配置目录、Agent 配置、本机覆盖项和排错。
- [日常使用（英文）](docs/usage.md)：tmux 会话编号、快捷键和 Shell 辅助命令。
- [工具清单（英文）](docs/tools.md)：工具用途和安装方式。
