# 预渲染素材的源文件

这里放用 [SpriteKiln](https://github.com/LucasJRamos/spritekiln)（MIT）渲染的魔物模型规格。Godot 不导入本目录（`.gdignore`）；渲染结果导出到 `res://assets/spritekiln/`，播放节点是 `res://addons/spritekiln/`（工具导出时自动装入的第三方插件，MIT，不需要在项目设置里启用）。

## 目录

- `spritekiln.toml`：工具的项目设置。
- `specs/characters/<名字>/<名字>.yaml`：一个模型一份规格。
- `specs/characters/*/out/`：渲染输出与缓存，不入库（见根目录 `.gitignore`）。

## 约定

- 每格 64 像素，帧尺寸 64。取景比例 `camera.scale` 决定魔物在帧里多大：苔是 0.036（一格一只），蚂蚁是 0.056（一格两只）。
- 侧视的模型用 `view: topdown` 加 `camera.pitch: 0`、`shadow: null`。不要写 `view: side`：它把方向限制为左右两个。
- 贴地爬的魔物分两份规格：`<名字>` 是 0° 侧视，只导出 `e`、`w`；`<名字>_top` 继承前者，只改相机为 90° 俯视，方向 `n`、`s`。两份共用骨骼和动作。
- 直立或不分腹背的魔物（如苔）只用一份规格，四个方向 `e, s, w, n` 都是 0° 侧视。固定不动的阶段（花苞、花）单独一份规格，只导出 `s`。
- 渲染时总是用 `--dirs` 写明方向；规格里的 `directions` 列表不一定生效。
- 颜色按材质固定，不能在一段动作里变色。发黄、闪白、消散这类效果在引擎里用 `scripts/fx/sprite_fx.gdshader` 做。
- 阶段转换不要求一个模型变成另一个：前一个模型演到交接姿势，后一个模型从同样的轮廓开始（苔的 `root_in` 接 `moss_plant` 的 `root`）。
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

苔的两份规格：

```powershell
.venv\Scripts\spritekiln render specs/characters/moss/moss.yaml --dirs e,s,w,n
```

```powershell
.venv\Scripts\spritekiln render specs/characters/moss_plant/moss_plant.yaml --dirs s
```

导出命令与蚂蚁相同，把规格路径换掉即可。

改造型时先用 `spritekiln pose <规格> --dirs e,w` 看单帧，不到一秒出图。
