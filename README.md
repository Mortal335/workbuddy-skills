# workbuddy-skills

一组面向 [Agent Skills](https://github.com/) 标准的技能包，可在 WorkBuddy 等支持
`SKILL.md` 约定的 agent 中加载使用。

## 技能列表

| 技能 | 说明 |
|---|---|
| [`github-skill-install`](./github-skill-install/SKILL.md) | 从 GitHub 仓库安装 Agent Skills 标准技能包，带**安装前安全审查**（危险模式扫描 + P0/P1/P2 分级）。 |
| [`github-release-parallel-download`](./github-release-parallel-download/SKILL.md) | 在国内网络环境下加速下载 GitHub Release 大文件：8 线程并行 Range 下载 + SHA256 校验 + Windows Authenticode 签名验证。 |

## 安装方式

技能目录约定为 `<skills_dir>/<name>/SKILL.md`。以用户级目录为例：

```bash
git clone --depth 1 https://github.com/Mortal335/workbuddy-skills.git "$HOME/workbuddy-skills"
mkdir -p ~/.workbuddy/skills
cp -r "$HOME/workbuddy-skills/github-skill-install" ~/.workbuddy/skills/
cp -r "$HOME/workbuddy-skills/github-release-parallel-download" ~/.workbuddy/skills/
```

也可以直接用 `github-skill-install` 技能来安装本仓库，它会先做一遍安全审查。

新装的技能通常在**新会话**中才会被加载。

## 许可

[MIT](./LICENSE)

## 说明

- 两个技能均针对 WorkBuddy 桌面端环境编写，部分步骤（如沙箱相关注意事项）在其他环境中未必适用。
- 仓库内不含任何密钥、凭据或本机私有路径。
