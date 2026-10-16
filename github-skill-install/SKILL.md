---
name: github-skill-install
description: >-
  从 GitHub 仓库安装 Agent Skills 标准技能包（带安装前安全审查）。当用户给出
  GitHub 仓库链接（如 https://github.com/org/repo 且仓库内含 SKILL.md）并希望安装
  为本地 skill 时使用。流程：浅克隆 → 安全审查（SKILL.md / package.json / 服务器脚本 /
  危险模式扫描）→ P0/P1/P2 分级 → 复制到 ~/.workbuddy/skills/<name>/ → 安装运行时
  依赖 → 冒烟测试 → 清理临时目录。仓库根目录不含 SKILL.md（如为子目录）时先定位
  skill 包路径再安装。
license: MIT
agent_created: true
metadata:
  version: "1.0.0"
---

# GitHub Skill 安装与审查流程

当用户要求安装一个 GitHub 上的 skill（Agent Skills 标准，仓库含 SKILL.md）时，按以下步骤执行。

## 安装前提

- 目标默认安装到**用户级**目录 `~/.workbuddy/skills/<folder>/`，除非用户明确要求项目级（`{workspace}/.workbuddy/skills/`）。
- 文件夹命名：优先用 SKILL.md frontmatter 里的 `name`；若已被占用或含义不清，用仓库名。
- skill 生效需要 SKILL.md 位于安装目录根（WorkBuddy 以 `<skills_dir>/<name>/SKILL.md` 发现技能）。新装技能通常在**新会话**中才被加载，需告知用户。

## 步骤 1 — 克隆仓库（注意 Windows /tmp 陷阱）

Git Bash 中 `/tmp` 可能不稳定（克隆后目录消失），**固定克隆到家目录**：

```bash
git clone --depth 1 <repo_url> "$HOME/skill-staging"
```

克隆前先 `rm -rf "$HOME/skill-staging"` 清理旧残留。

## 步骤 2 — 安全审查（安装前必做，向用户给出结论）

1. **读 SKILL.md**：检查 frontmatter（name/description/许可/触发词）、指引的命令是否仅限 localhost、有无要求下载执行不明文件。
2. **读 package.json**：依赖是否正常、有无 `postinstall`/`preinstall` 钩子、scripts 是否危险。
3. **读服务器/脚本源码**（如存在 .mjs/.js/.py）：确认监听地址、有无鉴权缺失、代码执行流向。
4. **全库危险模式扫描**（用 Grep 工具而非命令行 grep）：
   - 外联：`https?://`、`fetch(`、`webhook`、`ngrok`、`pastebin`、`.onion`
   - 凭据窃取：`api[_-]?key`、`secret`、`password`、`process\.env`、`document\.cookie`
   - 代码执行：`eval\(`、`child_process`、`spawn\(`、`exec`
   - 混淆：`\x[0-9a-fA-F]{2}`、`fromCharCode`、`base64` 大段硬编码
5. **检查载荷**：`find` 查 `.exe/.bat/.ps1/.sh/.vbs/.py/.zip` 等可执行文件；`git log -1` 看提交者。
6. **分级结论**：
   - **P0**：窃取凭据/外传数据/下载执行任意代码 → 拒绝安装并强烈警告。
   - **P1**：明显风险但非直接恶意（如安装钩子执行网络脚本）→ 警告并要求用户明确确认。
   - **P2**：安全可装，但记录注意事项（如无鉴权的本地服务端口、需手动运行的服务器等）。
   - 官方组织仓库 + MIT 许可 + 仅标准依赖 → 通常 P2。

## 步骤 3 — 安装

```bash
mkdir -p ~/.workbuddy/skills/<folder>
cp -r "$HOME/skill-staging/." ~/.workbuddy/skills/<folder>/
rm -rf ~/.workbuddy/skills/<folder>/.git
```

## 步骤 4 — 运行时依赖（如有 package.json）

用 WorkBuddy 托管 Node 的 npm 安装（避免污染用户全局环境）。托管 Node 位于
`~/.workbuddy/binaries/node/versions/<ver>/`，按本机实际版本号替换 `<ver>`：

```bash
cd ~/.workbuddy/skills/<folder>
NODE_HOME="$HOME/.workbuddy/binaries/node/versions/<ver>"
"$NODE_HOME/node.exe" "$NODE_HOME/node_modules/npm/bin/npm-cli.js" \
  install --omit=dev --no-audit --no-fund
```

## 步骤 5 — 冒烟测试（有可运行入口时）

本地回环服务类：后台启动 → `curl http://127.0.0.1:<port>/health` 验证 → `pkill -f <script>` 停止。

## 步骤 6 — 收尾

- `rm -rf "$HOME/skill-staging"` 清理。
- 向用户报告：安装路径、安全审查分级与注意事项、使用前提（如需要桌面端/扩展/账号）。
- 如与已装技能功能重叠（如不同机制的同域技能），向用户说明区别。
- 写入工作区日志：`.workbuddy/memory/YYYY-MM-DD.md`（路径随项目而变）。
