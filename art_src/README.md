# 预渲染素材的源文件

这里放用 [SpriteKiln](https://github.com/LucasJRamos/spritekiln)（MIT）渲染的魔物模型规格。Godot 不导入本目录（`.gdignore`）；渲染结果导出到 `res://assets/spritekiln/`，播放节点是 `res://addons/spritekiln/`（工具导出时自动装入的第三方插件，MIT，不需要在项目设置里启用）。

## 目录

- `spritekiln.toml`：工具的项目设置。
- `specs/characters/<名字>/<名字>.yaml`：一个模型一份规格。
- `specs/characters/*/out/`：渲染输出与缓存，不入库（见根目录 `.gitignore`）。

## 约定

- 每格 64 像素，帧尺寸 64，取景比例 `camera.scale: 0.036`。
- 侧视的模型用 `view: topdown` 加 `camera.pitch: 0`、`shadow: null`。不要写 `view: side`：它把方向限制为左右两个。
- 贴地爬的魔物分两份规格：`<名字>` 是 0° 侧视，只导出 `e`、`w`；`<名字>_top` 继承前者，只改相机为 90° 俯视，方向 `n`、`s`。两份共用骨骼和动作。
- 食物、菌团等先不做进模型。

## 重新渲染并导出

需要 Python 3.10 以上。工具装在任意虚拟环境里即可，不入库：

```powershell
python -m venv .venv; .venv\Scripts\pip install "spritekiln[fast]"
```

在本目录下执行（把 `..` 换成项目根目录的绝对路径也可以）：

```powershell
.venv\Scripts\spritekiln render specs/characters/ant/ant.yaml --dirs e,w
```

```powershell
.venv\Scripts\spritekiln render specs/characters/ant_top/ant_top.yaml
```

```powershell
.venv\Scripts\spritekiln godot specs/characters/ant/ant.yaml --project .. --dest assets/spritekiln
```

```powershell
.venv\Scripts\spritekiln godot specs/characters/ant_top/ant_top.yaml --project .. --dest assets/spritekiln
```

改造型时先用 `spritekiln pose <规格> --dirs e,w` 看单帧，不到一秒出图。
