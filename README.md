# workbuddy-skills

一组面向 [Agent Skills](https://github.com/) 标准的技能包，可在 WorkBuddy 等支持
`SKILL.md` 约定的 agent 中加载使用。

全部内容来自排障实战，重点是**把"看起来像玄学"的故障还原成可判定的因果链**。

---

## 技能列表

| 技能 | 说明 |
|---|---|
| [`electron-acl-fix`](./electron-acl-fix/SKILL.md) | 修复 Windows 上 Electron/Chromium 应用"双击没反应 / 闪退 / 白屏"，附可直接运行的 [`fix-acl.bat`](./electron-acl-fix/scripts/fix-acl.bat)。 |
| [`comfyui-portable-troubleshoot`](./comfyui-portable-troubleshoot/SKILL.md) | 排查 ComfyUI 整合包启动失败（8188 不通 / Manager 卡死 / bat 乱码 / `.pyc` 版本不匹配），并从 `.pyc` 前端提取 API 工作流模板做批量出图。 |
| [`github-skill-install`](./github-skill-install/SKILL.md) | 从 GitHub 仓库安装 Agent Skills 标准技能包，带**安装前安全审查**（危险模式扫描 + P0/P1/P2 分级）。 |
| [`github-release-parallel-download`](./github-release-parallel-download/SKILL.md) | 在国内网络环境下加速下载 GitHub Release 大文件：8 线程并行 Range 下载 + SHA256 校验 + Windows Authenticode 签名验证。 |

---

## 深入：Electron / Chromium 应用为什么"打不开"

这是本仓库里排得最久、也最反直觉的一类故障。症状五花八门 —— 有的双击毫无反应、
有的闪一下就没、有的白屏、有的任务管理器里能看到进程但桌面上永远没有窗口 ——
**根因却只有一条**。

### 症状与根因

安装目录的 DACL 里缺少 **`S-1-15-2-2`**
（`APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES`，
中文系统里显示为「所有受限制的应用程序包」）。

Win11 24H2 / 25H2 上，Electron 的 Chromium 子进程（`renderer` / `gpu-process` /
`utility`）会以 **AppContainer 受限令牌**启动。Windows 加载器在读取程序目录内的
DLL 时被 ACL 拒绝，**但它把这个"权限拒绝"映射成了 `STATUS_DLL_NOT_FOUND`** ——
于是日志里写的是"找不到 DLL"，而 DLL 其实一个不缺。这就是整类故障的指纹。

> 先排除：**不要**往显卡驱动、VC++ 运行库、中文路径、杀毒软件方向查 ——
> 这些在本类故障中已被反复证伪，查下去只会白耗时间。

### 关键判据：退出码签名

主进程和它的子进程是两回事。主进程活着、子进程崩了，表现就是"没窗口"。

| 值 | 十六进制 | 含义 |
|---|---|---|
| `-2147483645` | `0x80000003` | `STATUS_BREAKPOINT` —— **主进程**最终退出码，本故障的固定签名 |
| `-1073741515` | `0xC0000135` | `STATUS_DLL_NOT_FOUND` —— **GPU 子进程**退出码 |
| `-1073741760` | `0xC0000022` | `STATUS_ACCESS_DENIED` —— 另一种子进程退出码 |

**决定性判读**：报了 `DLL_NOT_FOUND`，但 `libGLESv2.dll` / `libEGL.dll` /
`d3dcompiler_47.dll` / `vk_swiftshader.dll` / `icudtl.dat` **一个不少却仍说找不到**
→ 那是权限被映射成了缺失，**不是文件缺失**。

### 表现形态对照

| 观察 | 含义 |
|---|---|
| 进程数 0，日志停在模块初始化（logger / db / menu / tray / server 都走完了，**没有任何一行"窗口创建"**） | 闪退型（最典型） |
| 有 `main`，`renderer` = 0 | 白屏型（界面全空） |
| 有 `main`，`gpu-process` 反复崩 | GPU 子进程型 |

### 30 秒定性实验

```powershell
Start-Process -FilePath "<安装目录>\<app>.exe" -ArgumentList '--no-sandbox' -PassThru
```

**窗口能出来就 100% 坐实是那条 ACE 的问题**（`--no-sandbox` 让子进程改回普通令牌、
不再校验程序目录 DACL）。

⚠️ 这只是**诊断手段**，不是修复方案（牺牲了 renderer 沙箱）。用完必须杀掉该实例，
否则它会占着端口，让后面正常启动被 `EADDRINUSE` 顶掉 —— **这会让你误判修复失败**。

### 修复

```powershell
icacls "<安装目录>" /grant "*S-1-15-2-2:(RX)" /T /C
```

- **必须用 `(RX)`，不要用 `(OI)(CI)(RX)`**：若目录继承链被阻断（DACL 全是显式项、
  没有 `(I)`），`(OI)(CI)` 的 ACE 只会落在目录上、**传不到文件**，而 `icacls`
  仍报「0 失败」（**虚假成功**）→ 修完必须复查 exe 文件本身。
- **判定必须用 SDDL**：`$acl.Sddl -match 'S-1-15-2-2'`。
  不要用 `IdentityReference.Translate()` 遍历比较 —— 它会给**已修好的目录也报缺失**。
- **要不要提权看 `Owner`**：owner 是当前用户（`%LOCALAPPDATA%\Programs\`）→ 免提权；
  owner 是 `BUILTIN\Administrators`（装到 `D:\` 的那种）→ **必须提权**，
  否则非提升会话会清一色「拒绝访问」。

### 为什么修完还会复发

| 场景 | 结果 |
|---|---|
| 应用自动更新 | ❌ 复发。新文件不会自动带上这条 ACE，更新后要重跑一次 |
| 同盘 `MoveFile` 移动 | ✅ 保留。只改目录树链接、不重算继承 |
| 复制 / 跨盘移动 | ❌ 全丢。新文件从新父目录继承，补丁没了 |
| 装在 `C:\Program Files` 下 | ✅ 默认自带该 ACE，不受影响（可用作反证） |

想一次性根治整个盘（需管理员）：

```powershell
icacls "D:\" /grant "*S-1-15-2-2:(OI)(CI)(RX)"
```

### 附带的一个 cmd.exe 冷知识

**`.bat` 里的 `rem` 行绝不要出现 `>`** —— cmd.exe 在解析阶段就会把它当重定向处理，
于是静默创建一个名为 `fix` 之类的垃圾文件，而 `rem` 的文字被截断。
本仓库的 `fix-acl.bat` 已改为用 `:` 分隔说明文字。

---

## 深入：ComfyUI 整合包启动失败的三条因果链

整合包（便携版 / 一键包）在 Windows 上起不来，绝大多数落在下面三条链里。
先看日志的**报错指纹**，就能直接跳到对应链条：

| 报错指纹 | 根因 | 链条 |
|---|---|---|
| `ConnectionRefusedError WinError 10061` 指向 `:8188/prompt`；日志已打印 `To see the GUI go to: http://127.0.0.1:8188` 但 `netstat` 查不到 LISTENING | ComfyUI-Manager 在启动阶段强联网被阻塞，主服务还没真正进入监听 | A |
| 启动日志刷 `FETCH ComfyRegistry Data: n/190` 后卡死 | 同上，`network_mode=public` 强联网 | A |
| `'xxx' 不是内部或外部命令`（奇怪截断/乱码） | bat 是 LF 换行或 UTF-8 编码，cmd 逐字节块读取时错位 | B |
| 中文提示语变 `鍚庣` 之类乱码 | bat 被 cmd 按 GBK 解析 UTF-8 内容 | B |
| `RuntimeError: Bad magic number in .pyc file` | 用了错误的 Python 版本跑 `.pyc` | C |
| 报错里出现系统 Python 路径（如 `C:\Python314\Scripts`） | bat 没显式指定便携版解释器，被系统 Python 抢占 | C |

**链条 A** 的修法：把 `<ComfyUI>/user/__manager/config.ini` 或
`user/default/ComfyUI-Manager/config.ini` 里的 `network_mode` 由 `public` 改为
`offline`，并给启动命令加 `--disable-auto-launch`。离线模式下典型就绪时间
**20–30 秒**；改前若需 4 分钟以上或始终不就绪，即为链条 A。

**链条 B** 的铁律（全部满足，否则 cmd.exe 解析必炸）：bat 内容**纯 ASCII**（提示语
用英文）、换行**必须 CRLF**、用 `chcp 936` 而非 UTF-8 + `chcp 65001`、
`set "VAR=VALUE"` 加引号防路径空格、路径统一 `%~dp0` 且**显式写全解释器路径**、
**`%PATH%` 放在最后**避免被系统 Python 抢占。

**链条 C** 的要点：整合包里的 `.pyc` 是用它自带的 Python 编译的，**必须用同一个
解释器运行**。读 magic number 对照：`3531`=3.12 / `3495`=3.11 / `3425`=3.10 /
`3621`=3.14。

### 进阶：从 `.pyc` 前端提取 API 工作流模板

整合包的 Gradio 前端常是 `.pyc`（源码不可见），但它内部**硬编码了可用的 API
工作流模板**。拦截 `gradio.Blocks.launch` / `queue` 后 `marshal.loads(data[16:])`
即可无副作用加载，再把 `WORKFLOW_TEMPLATES` / `SIZE_PRESETS` 等常量捞出来，
就能写自己的批量出图脚本，完全不依赖前端界面。

细节（含多图对比两种方案的取舍、显存约束、端到端验证方法）见技能正文。

---

## 安装方式

技能目录约定为 `<skills_dir>/<name>/SKILL.md`。以用户级目录为例：

```bash
git clone --depth 1 https://github.com/Mortal335/workbuddy-skills.git "$HOME/workbuddy-skills"
mkdir -p ~/.workbuddy/skills
for s in electron-acl-fix comfyui-portable-troubleshoot \
         github-skill-install github-release-parallel-download; do
  cp -r "$HOME/workbuddy-skills/$s" ~/.workbuddy/skills/
done
```

也可以直接用 `github-skill-install` 技能来安装本仓库，它会先做一遍安全审查。

新装的技能通常在**新会话**中才会被加载。

---

## 许可

[MIT](./LICENSE)

## 说明

- 技能均针对 WorkBuddy 桌面端环境编写，部分步骤（如沙箱相关注意事项）在其他环境中未必适用。
- 仓库内不含任何密钥、凭据或个人私有路径；`fix-acl.bat` 只接受显式传入的目标目录，
  日志写入 `%TEMP%`。
