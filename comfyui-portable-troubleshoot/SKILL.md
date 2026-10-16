---
name: comfyui-portable-troubleshoot
description: 排查 ComfyUI 整合包（便携版/一键包）在 Windows 上的启动失败问题、生成可靠的 Windows .bat 启动脚本，以及从整合包 .pyc 前端提取 API 工作流模板来做批量出图。当用户遇到连接 8188 被拒、ComfyUI-Manager 启动卡死、bat 中文乱码、'xxx 不是内部或外部命令'、'Bad magic number in .pyc file'、Gradio 前端连不上后端，或想给整合包写批量生成脚本时使用。
license: MIT
agent_created: true
metadata:
  version: "1.0.0"
---

# ComfyUI 整合包 Windows 启动故障排查

## 症状 → 根因速查表

| 报错 | 根因 | 修复 |
|---|---|---|
| `ConnectionRefusedError WinError 10061` 指向 `:8188/prompt` | ComfyUI 后端未 LISTENING | 见「故障 A」 |
| 启动日志刷 `FETCH ComfyRegistry Data: n/190` 后卡死 | Manager `network_mode=public` 强联网 | 见「故障 A」 |
| `'xxx' 不是内部或外部命令`（奇怪截断/乱码） | bat 是 UTF-8 或 LF 换行 | 见「故障 B」 |
| 中文提示语变 `鍚庣` 之类乱码 | bat 被 cmd 按 GBK 解析 UTF-8 | 见「故障 B」 |
| `RuntimeError: Bad magic number in .pyc file` | 用了错误的 Python 版本跑 .pyc | 见「故障 C」 |
| 报错里出现系统 Python 路径（如 `C:\Python314\Scripts`） | bat 没显式指定便携版解释器 | 见「故障 C」 |

## 故障 A：8188 端口不通（最常见）

**关键认知**：日志已打印 `To see the GUI go to: http://127.0.0.1:8188`，但端口 `netstat` 查不到 LISTENING —— 这是 **ComfyUI-Manager 在启动阶段强联网被阻塞**，主服务还没真正进入监听。

```bash
# 1. 确认端口状态
netstat -ano | grep ":8188"
# 2. 看日志是否有大量 FETCH
tail -50 <ComfyUI>/user/comfyui.log
```

**修复**：改 `<ComfyUI>/user/__manager/config.ini`（或 `user/default/ComfyUI-Manager/config.ini`）：

```ini
network_mode = offline     # 从 public 改为 offline
```

同时给启动命令加 `--disable-auto-launch`。

**辅助定位**：日志里的路径能告诉你这是否是本机日志。整合包常见混淆 —— 别人机器路径的旧日志混在 `user/` 目录里，别被误导，认准 `Log path:` 那行。

## 故障 B：Windows .bat 写法铁律

**必须全部满足**，否则 cmd.exe 解析必炸：

1. **内容必须纯 ASCII** — 绝不在 bat 里写中文。提示语用英文。
2. **换行必须是 CRLF** — 纯 LF 会让 cmd 把多行粘成一行执行，产生 `'e-packages' 不是内部或外部命令` 这种诡异截断报错。
3. **编码用 ASCII/GBK**，配 `chcp 936`；不要用 UTF-8 + `chcp 65001` 的写法。
4. `set "VAR=VALUE"` 要加引号，防路径空格。
5. 路径统一用 `%~dp0`，并**显式写全解释器路径**。
6. **`%PATH%` 要放在最后**，避免被系统 Python 抢占。

**标准模板**：

```bat
@echo off
chcp 936 >nul
title App Name
cd /d "%~dp0"

set "PYTHONUSERBASE=%~dp0python\Lib\site-packages"
set "PYTHONPATH=%~dp0python\Lib\site-packages"
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
set "PATH=%~dp0python;%~dp0python\Scripts;%PATH%"

"%~dp0python\python.exe" -s "%~dp0app\main.py"

echo.
echo [App exited] Press any key to close...
pause >nul
```

**转换已有 bat 为合规格式**（用系统 Python 跑）：

```python
fn = 'target.bat'
t = open(fn, 'rb').read().decode('utf-8')
t = t.replace('\r\n', '\n').replace('\n', '\r\n')   # 强制 CRLF
open(fn, 'wb').write(t.encode('ascii'))             # 强制 ASCII
```

**校验**：

```python
d = open(fn, 'rb').read()
assert d.replace(b'\r\n', b'').count(b'\n') == 0   # 无裸 LF
assert all(c < 128 for c in d)                     # 纯 ASCII
```

## 故障 C：.pyc 版本不匹配

```bash
# 读 .pyc 的 magic number
python -c "import struct;d=open('demo.pyc','rb').read(4);print(struct.unpack('<H',d[:2])[0])"
```

对照表：`3531`=3.12 / `3495`=3.11 / `3425`=3.10 / `3621`=3.14（新版本递增）。

**要点**：整合包里的 `.pyc` 是用它自带的 Python 编译的，**必须用同一个解释器运行**。报错里若出现系统 Python 路径，说明 bat 用了 `python` 裸命令，改成显式全路径即可。

## 验证启动成功的标准

```bash
curl -s http://127.0.0.1:8188/system_stats    # 应返回 JSON 含 comfyui_version
curl -s http://127.0.0.1:8188/object_info     # 节点列表，json 长度即节点数
```

离线模式下典型就绪时间为 **20-30 秒**。改前若需 4 分钟以上或始终不就绪，即为故障 A。

## 排查顺序建议

1. `netstat -ano | grep -E ":(7860|8188)"` — 先分清前端/后端谁没起
2. 读最新 `user/comfyui.log`（认准 Log path 行，避开外来旧日志）
3. 看有无 `FETCH` 卡顿 → 故障 A
4. 报错含 `不是内部或外部命令` → 故障 B
5. 报错含 `Bad magic number` → 故障 C

---

# 进阶：从 .pyc 前端提取 API 工作流模板

整合包的 Gradio 前端常是 `.pyc`（源码不可见），但它内部**硬编码了可用的 API 工作流模板**。提取出来就能写自己的批量出图脚本，不依赖前端界面。

## 无副作用加载 .pyc

拦截 `gradio.Blocks.launch`/`queue`，避免真的起服务：

```python
import marshal, types, gradio
gradio.Blocks.launch = lambda self, *a, **k: None
gradio.Blocks.queue = lambda self, *a, **k: self

mod = types.ModuleType('demo_mod')
mod.__file__ = r'D:\path\to\demo.pyc'
data = open(mod.__file__, 'rb').read()
exec(marshal.loads(data[16:]), mod.__dict__)   # 跳过 16 字节 pyc 头
```

**必须用与 .pyc 匹配的 Python 版本执行**（否则 `Bad magic number`）。

## 摸索内部结构

```python
# 1. 看模块级变量名，找模板/节点常量
print(mod.__dict__.keys())
print([n for n in top.co_names if 'TEMPLATE' in n or 'NODE' in n])

# 2. 递归收集字符串常量，找关键词
def allstr(c, out):
    for k in c.co_consts:
        if isinstance(k, str): out.append(k)
        elif hasattr(k, 'co_consts'): allstr(k, out)
    return out
```

## 常见可提取物

| 名称 | 含义 |
|---|---|
| `WORKFLOW_TEMPLATES` | dict：模板 key → API 工作流（节点字典） |
| `SIZE_PRESETS` | dict：尺寸标签 → (width, height) |
| `*_OUTPUT_NODE` / `*_PROMPT_NODE` 等 | 节点 ID 字符串常量 |
| `COMFYUI_BASE_URL` / `PROMPT_URL` | 后端地址与端点 |

**关键陷阱**：模板 key 与节点 ID 可能数字巧合相同但含义完全不同。务必实测确认对应关系，不要按名字推断。

## 端到端验证方法

```python
# 1. 提交测试任务，检查 node_errors 是否为空
r = requests.post('http://127.0.0.1:8188/prompt', json={'prompt': wf})
print(r.json())          # 期望 {"prompt_id": "...", "node_errors": {}}

# 2. 轮询 /history/{prompt_id} 直到 status_str == "success"
# 3. 从 outputs[输出节点ID]['images'] 取文件名，走 /view 下载
```

`node_errors: {}` 为空是节点连接、模型文件名全部正确的强证据。

## 批量出图脚本骨架

```python
def build_workflow(templates, mode, prompt, seed, w, h):
    wf = json.loads(json.dumps(templates[tpl_key]))   # 深拷贝！
    wf[prompt_node]['inputs']['value'] = prompt
    wf[latent_node]['inputs']['width'] = w
    wf[latent_node]['inputs']['height'] = h
    wf[sampler_node]['inputs']['seed'] = seed
    wf[neg_node]['inputs']['text'] = negative
    return wf, output_node

resp = requests.post(PROMPT_URL, json={'prompt': wf}, timeout=60)
prompt_id = resp.json()['prompt_id']
# 轮询 history → 下载 view
```

要点：
- **必须深拷贝模板**（`json.loads(json.dumps(...))`），否则会污染后续任务
- 首次生成要加载 10GB 模型，耗时长；同模式第二张会快很多
- 显存不足时降低尺寸，而不是改 batch_size

## 多图对比：两种方案怎么选

用户要"一次出多张方便对比"时，先分清他要对比什么：

| 方案 | 做法 | 种子 | 结果 | 显存 |
|---|---|---|---|---|
| A 批量 | `EmptyLatentImage.batch_size = N`，一次提交 | 相同 | 构图一致，细节微变 | **xN，容易爆** |
| B 循环 | 提交 N 次，每次不同种子 | 不同 | **构图完全不同** | 恒定 |

**判断规则**：要"挑构图" → 用 B；要"同构图挑细节" → 用 A。8GB 显存优先 B。

方案 B 实现要点：

```python
for k in range(count):
    seed = random.randint(0, 2**63-1) if base_seed < 0 else base_seed + k
    wf, out = build_workflow(tpl, task, batch_size=1, seed_override=seed)
    submit_and_wait(wf)
```

**对比图拼接**（Pillow，通常已随整合包提供）：

```python
from PIL import Image, ImageDraw
imgs = [Image.open(p).convert('RGB') for p in paths]
w, h = imgs[0].size
gap, label_h = 12, 34
canvas = Image.new('RGB', (w*len(imgs)+gap*(len(imgs)-1), h+label_h), (245,245,245))
draw = ImageDraw.Draw(canvas)
for i, im in enumerate(imgs):
    x = i*(w+gap)
    canvas.paste(im.resize((w,h)), (x, label_h))
    draw.text((x+6, 10), f'#{i+1}', fill=(60,60,60))
canvas.save('对比图.png')
```

**实测性能参考**：512×512 turbo 第 1 张含加载 15s，第 2 张仅 4s（模型驻留显存）。

## 尺寸兼容性提醒

原生训练分辨率通常非 16:9。用户要求非标准比例（如 1280×720）时**要主动提示构图风险**，建议先试一张，异常则回退到官方预设比例。
