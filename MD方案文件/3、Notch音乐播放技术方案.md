# Notch 音乐播放技术方案

日期：2026-05-02  
更新：2026-05-05

## 1. 目标

为刘海屏工具箱中的音乐播放模块提供一套可落地的外部播放器控制、状态同步与低能耗运行方案，满足以下目标：

- 支持外部播放器控制：播放、暂停、上一首、下一首、进度拖拽
- 支持歌曲信息读取：封面、歌曲名、歌手名、专辑名、时长、当前播放器来源
- 支持未播放态下的播放器启动入口
- 支持折叠态与展开态两套展示模型
- 在第三方播放器时间源不稳定的情况下，仍保持用户可接受的进度显示一致性
- 在面板关闭后进入休眠，不保留无意义高频刷新
- 为后续接入刘海屏面板提供可复用的播放器适配层、状态层与时间轴层

当前产品范围内的目标播放器：

- Apple Music
- 网易云音乐
- QQ 音乐
- 酷狗音乐
- 汽水音乐
- Spotify

当前优先验证并已通过核心控制验证的播放器：

- QQ 音乐
- 网易云音乐
- 酷狗音乐
- 汽水音乐

---

## 2. 技术结论

结论分为三层：

1. `MediaRemote / Now Playing` 能稳定提供大部分歌曲元数据与基础控制能力，但第三方播放器在 `elapsedTime` 与 `calculatedPlaybackPosition` 上存在明显不一致。
2. 直接信任系统时间源会导致暂停回退、seek 偏移、进度跳变。更稳的做法是：`本地时间轴为主，系统值只做校准`。
3. 正式产品不能只解决“进度同步”，还必须同时定义：`播放器发现与启动`、`多播放器能力分层`、`折叠/展开状态切换`、`低能耗调度`、`权限与失败降级路径`。

因此本方案正式分为：

- `备选方案一`：系统时间源直读 + 前端纠偏
- `当前主方案`：播放器适配层 + 会话状态层 + 本地时间轴层 + UI 状态层

---

## 3. 备选方案一

### 3.1 定义

直接使用系统提供的播放时间字段驱动 UI：

- `rawElapsedTime`
- `calculatedPlaybackPosition`
- `playbackRate`

前端再增加：

- 播放态补间
- 暂停冻结
- 暂停宽限期保护
- 同曲暂停态防回退

### 3.2 优点

- 实现简单
- 与系统时间源贴近
- 元数据和控制链路耦合更低

### 3.3 问题

- 第三方播放器常出现时间源脏数据
- 播放中 `calculatedPlaybackPosition` 和暂停后 `rawElapsedTime` 可能分叉严重
- seek 后会被旧系统值拉偏
- 暂停后可能固定回退到旧时间点
- 无法很好承接折叠态、空态、拖拽中、权限失败态等更完整的模块状态

### 3.4 结论

保留为备选方案，不建议作为默认方案。

---

## 4. 当前主方案

### 4.1 核心原则

当前主方案的总原则是：

`播放器能力分层 + 模块状态分层 + 本地时间轴为主，系统值只做校准`

具体含义：

- UI 展示的进度不再直接等于系统返回的单次时间值
- UI 不直接面向某个播放器，而是面向统一的 `PlaybackSession`
- 未播放态、折叠态、展开态、暂停态、异常态分别单独建模
- 用户操作优先改变本地状态
- 系统返回值只有在满足校准条件时才接管时间轴
- 面板关闭后进入休眠，不维持无意义的高频状态构建

### 4.2 推荐分层

建议正式采用以下四层结构：

- `PlayerRegistry / Adapter 层`
  - 负责发现支持的播放器
  - 负责播放器启动
  - 负责按播放器差异提供控制实现
  - 负责输出“该播放器支持哪些能力、哪些已验证”
- `PlaybackSession 层`
  - 负责确定当前活跃播放器
  - 负责维护当前歌曲元数据、播放状态、来源 bundle id、验证状态
  - 负责把底层脏数据整理成统一会话对象
- `CanonicalTimeline 层`
  - 负责本地时间轴
  - 负责暂停、seek、切歌、系统值校准
  - 负责对外提供稳定的进度状态
- `MusicModuleState 层`
  - 负责空态、折叠态、展开态、权限失败态、不可控态、恢复态
  - 负责根据当前状态决定是否展示启动入口、封面、按钮、进度条和异常提示

这样拆分后，音乐模块不再只是“一个轮询脚本 + 一条进度条”，而是一个正式产品模块。

### 4.3 播放器能力模型

每个播放器都必须显式声明能力，不允许在 UI 层默认假设“全都能控制、全都能拖动、全都能启动”。

建议定义：

```ts
type PlayerCapability = {
  bundleId: string
  displayName: string
  launch: "verified" | "target" | "unsupported"
  metadata: "verified" | "target" | "unsupported"
  playPause: "verified" | "target" | "unsupported"
  prevNext: "verified" | "target" | "unsupported"
  seek: "verified" | "target" | "unsupported"
  collapsedIndicator: "verified" | "target" | "unsupported"
  notes?: string
}
```

当前能力矩阵建议写成：

| 播放器 | 启动 | 元数据 | 播放/暂停 | 上一首/下一首 | seek | 折叠态展示 | 当前状态 |
|---|---|---|---|---|---|---|---|
| QQ 音乐 | verified | verified | verified | verified | verified | verified | 已验证 |
| 网易云音乐 | verified | verified | verified | verified | verified | verified | 已验证 |
| 酷狗音乐 | verified | verified | verified | verified | verified | verified | 已验证 |
| 汽水音乐 | verified | verified | verified | verified | verified | verified | 已验证 |
| Apple Music | target | target | target | target | target | target | 目标接入 |
| Spotify | target | target | target | target | target | target | 目标接入 |

说明：

- `verified` 代表已完成人工验证，可对外承诺
- `target` 代表属于产品目标范围，但当前不能对外承诺为“稳定支持”
- UI 必须根据该矩阵决定文案与交互，不得用产品文案掩盖真实能力边界

### 4.4 模块状态模型

当前产品与设计稿至少包含以下状态：

- `idle`
  - 模块未激活，面板关闭
- `collapsedPlaying`
  - 折叠态播放中
  - 展示左侧播放器 Logo 和右侧动态播放提示
- `expandedEmpty`
  - 展开后无活动播放会话
  - 展示“美好的一天，从音乐开始”与播放器启动入口
- `expandedPlaying`
  - 展开后正在播放
  - 展示封面、歌曲名、歌手、进度、暂停按钮、上一首、下一首
- `expandedPaused`
  - 展开后当前歌曲暂停
  - 展示封面、歌曲名、歌手、进度、播放按钮、上一首、下一首
- `expandedSyncRecovering`
  - 刚发生 seek / pause / resume / 切歌，仍在等待系统值稳定
- `expandedPermissionRequired`
  - 控制或读取依赖权限未满足
- `expandedUnsupported`
  - 当前识别到播放器，但不在当前支持名单或能力不足
- `launchingPlayer`
  - 用户从空态点击播放器图标后，正在尝试启动播放器

建议定义：

```ts
type MusicModuleState =
  | { kind: "idle" }
  | { kind: "collapsedPlaying"; session: PlaybackSession }
  | { kind: "expandedEmpty"; launchablePlayers: PlayerCapability[] }
  | { kind: "launchingPlayer"; targetBundleId: string }
  | { kind: "expandedPlaying"; session: PlaybackSession; timeline: CanonicalTimeline }
  | { kind: "expandedPaused"; session: PlaybackSession; timeline: CanonicalTimeline }
  | { kind: "expandedSyncRecovering"; session: PlaybackSession; timeline: CanonicalTimeline }
  | { kind: "expandedPermissionRequired"; reason: PermissionReason }
  | { kind: "expandedUnsupported"; bundleId: string; displayName?: string }
```

### 4.5 会话状态结构

建议增加统一会话层，而不是让 UI 直接消费多个来源的散乱字段：

```ts
type PlaybackSession = {
  bundleId: string
  displayName: string
  trackKey: string | null
  title: string | null
  artist: string | null
  album: string | null
  artworkUrl: string | null
  duration: number | null
  playbackState: "playing" | "paused" | "stopped" | "unknown"
  capability: PlayerCapability
  isVerifiedPlayer: boolean
  source: "mediaremote" | "nowplaying-cli" | "adapter-fallback"
  lastUpdatedAtMs: number
}
```

### 4.6 本地时间轴结构

建议前端维护以下结构：

```ts
type CanonicalTimeline = {
  trackKey: string
  playbackState: "playing" | "paused" | null
  anchorElapsed: number
  duration: number
  anchorTimeMs: number
  lastSystemElapsed?: number
  lastSystemUpdateMs?: number
  intent: null | {
    type: "play" | "pause" | "seek"
    startedAtMs: number
    graceMs: number
    targetElapsed?: number
  }
}
```

说明：

- `PlaybackSession` 负责表达“播放器现在是什么状态”
- `CanonicalTimeline` 负责表达“UI 当前该显示什么进度”
- 这两个对象必须分离，避免状态耦合混乱

### 4.7 `trackKey` 规则

原方案里的 `title + artist + album + duration` 仍可作为基础，但正式产品不能直接裸用，建议改为“带归一化和容错的组合键”：

`bundleId + normalizedTitle + normalizedArtist + normalizedAlbum + normalizedDurationBucket`

建议规则：

- 文本先做 trim、大小写归一、全角半角归一
- `album` 缺失时允许降级
- `duration` 用 bucket，而不是裸秒值
- 新旧 `trackKey` 在短时间窗口内允许做一次模糊同曲判定，避免同一首歌元数据微调导致重建时间轴

用于判断：

- 当前轮询结果是否仍是同一首歌
- 是否允许沿用当前本地时间轴
- 是否需要切歌后重建时间轴

### 4.8 播放逻辑

播放中：

- 前端根据 `anchorElapsed + (now - anchorTimeMs)` 本地补间
- 系统值只用于周期性校准
- 如果系统值明显落后于本地时间轴，不直接采用
- 若当前模块处于折叠态，只维护轻量状态，不做展开态所需的额外 UI 计算

### 4.9 暂停逻辑

点击暂停时：

- 立即冻结当前显示进度
- 本地时间轴切换到 `paused`
- 创建 `pause intent`
- UI 立即切到暂停按钮对应的展开态

暂停确认阶段：

- 宽限期内，如果系统仍返回 `playing`，忽略旧值
- 当系统返回 `paused` 时，允许确认暂停
- 如果系统暂停值小于当前本地时间轴，不允许回退

### 4.10 Seek 逻辑

用户拖动进度条时：

- UI 立即落到拖拽目标位置
- 本地时间轴立即更新到目标位置
- 创建 `seek intent`
- 模块短时进入 `expandedSyncRecovering`

Seek 校准阶段：

- 在宽限期内，忽略明显偏离目标位置的旧系统值
- 只有当系统返回的位置接近目标值时，才认为 seek 已确认
- 若超出宽限期仍未确认，可继续保留本地时间轴，等待下一轮稳定值
- 若播放器根本不支持 seek，则 UI 不应暴露可拖拽交互

### 4.11 切歌逻辑

如果系统轮询返回的 `trackKey` 变化：

- 直接视为新曲
- 重建本地时间轴
- 清空上一个 `intent`
- 根据新会话状态决定进入 `expandedPlaying` 或 `expandedPaused`

### 4.12 空态与启动逻辑

当不存在活动播放会话时：

- 模块进入 `expandedEmpty`
- 展示播放器启动入口
- 播放器顺序与产品文档保持一致

用户点击启动入口时：

- 模块切换为 `launchingPlayer`
- 调用对应播放器适配器的 `launch()` 能力
- 启动成功后等待会话出现，再进入播放态或暂停态
- 若超时未出现可识别会话，回退到空态并给出失败提示

---

## 5. 控制与信息链路

### 5.1 信息读取

优先使用：

- `MediaRemote / Now Playing`
- `nowplaying-cli`

读取：

- 标题
- 歌手
- 专辑
- 封面
- 时长
- 当前播放器 bundle id
- 播放状态

读取策略：

- `MediaRemote / Now Playing` 作为主元数据来源
- 若特定字段缺失，则允许由播放器 adapter 做补齐
- 所有来源最终统一汇总到 `PlaybackSession`

### 5.2 播放器发现与活跃会话仲裁

正式产品不能默认“谁最后返回数据就用谁”，需要显式仲裁：

- 若只有一个受支持播放器处于活动播放态，则直接认定为当前会话
- 若多个播放器同时存在会话，优先选择当前系统媒体会话
- 若多个播放器同时暂停且都可见，优先选择最近一次处于 `playing` 的播放器
- 若识别到受支持外的播放器，则进入 `expandedUnsupported`

建议额外维护：

```ts
type ActiveSessionResolverResult = {
  active: PlaybackSession | null
  candidates: PlaybackSession[]
  reason: "single" | "system-media-session" | "recent-active" | "none" | "unsupported"
}
```

### 5.3 播放控制

当前以适配器方式实现，不再在方案里把特殊逻辑散落到 UI 层：

- QQ 音乐优先使用菜单控制
- 其他播放器优先走系统级媒体控制
- 如系统级控制失败，可按播放器差异增加 adapter fallback

能力范围：

- 播放 / 暂停
- 上一首
- 下一首
- 进度拖拽
- 启动播放器

### 5.4 启动控制

空态里的播放器图标不是静态装饰，而是正式交互入口，因此技术方案必须定义：

- 通过 bundle id 或 app path 启动目标播放器
- 启动时不强依赖其立刻开始播放
- 启动成功但尚无会话时，UI 保持短暂等待态
- 未安装时提示“未安装”
- 已安装但无法拉起时提示“启动失败，请手动打开”

### 5.5 折叠态链路

折叠态只展示：

- 当前播放器 Logo
- 动态播放提示

折叠态不展示：

- 封面
- 全量按钮
- 实时文本时间

因此折叠态的状态构建必须比展开态更轻：

- 只关心 `bundleId`
- 只关心是否处于 `playing`
- 不需要持续计算完整展开态文案与控制组

---

## 6. 当前验证结果与对外承诺边界

已完成人工验证的播放器：

| 播放器 | 启动 | 进度拖拽 | 暂停 | 开始 | 上一首 | 下一首 | 结果 |
|---|---|---|---|---|---|---|---|
| QQ 音乐 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 |
| 网易云音乐 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 |
| 酷狗音乐 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 |
| 汽水音乐 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 | 通过 |

当前验证结论：

- `方案二` 在这 4 个目标播放器上已具备成立条件
- 进度条拖拽、暂停、开始、上一首、下一首都已通过人工验证
- 启动入口也应纳入正式验证矩阵，而不是只验证播放内控制
- Apple Music 与 Spotify 当前属于产品目标接入，不写为“稳定支持”

对外承诺规则：

- 文案里只能把 `verified` 能力写成“支持”
- 对 `target` 能力只能写成“计划接入 / 目标接入”
- 设置页、帮助文档、空态引导都必须复用同一套能力矩阵

---

## 7. 性能与能耗策略

### 7.1 前端成本

当前前端进度补间约为：

- 展开播放态下每 `250ms` 刷新一次显示时间和进度条

这部分只涉及：

- 一个 range 值更新
- 两个文本更新时间

浏览器 Demo 阶段性能压力很低，但正式产品需要与模块状态联动，不应全时运行。

### 7.2 服务端成本

当前服务端状态轮询链路仍然偏重，主要包括：

- `nowplaying-cli get-raw`
- JXA 读取 `calculatedPlaybackPosition`
- `System Events` 读取菜单和进程状态

因此：

- 用作验证 Demo：可以接受
- 用作正式常驻产品：必须分状态降频

### 7.3 分状态调度策略

建议正式采用以下轮询分级：

| 模块状态 | 建议策略 |
|---|---|
| `idle` | 不做高频轮询，只保留极低频会话探测 |
| `collapsedPlaying` | 低频维护播放器来源与播放态 |
| `expandedEmpty` | 低频探测是否出现新会话 |
| `expandedPlaying` | 中高频维护时间轴与控制反馈 |
| `expandedPaused` | 低频维护暂停态与元数据 |
| `expandedSyncRecovering` | 短时提高频率，确认 seek / pause / resume |
| `launchingPlayer` | 短时提高频率，等待播放器会话建立 |
| `sleep / wake transition` | 暂停轮询，唤醒后重建一次会话 |

原则：

- 只有用户正在看、正在操作时，才允许提升频率
- 面板关闭后不得延续展开态频率
- 短时升频必须有自动回落机制

---

## 8. 权限、失败路径与降级策略

### 8.1 权限依赖

当前方案涉及：

- 系统媒体会话读取
- JXA
- `System Events`
- 菜单控制

正式产品必须明确以下权限或能力前提：

- 若缺少自动化权限，某些播放器控制可能失败
- 若缺少辅助功能权限，某些菜单控制可能失败
- 若播放器未安装，则空态启动入口只能提示未安装

### 8.2 失败路径

建议至少定义以下失败态：

- 播放器未安装
- 播放器已安装但启动失败
- 播放器已启动但未建立可识别会话
- 元数据读取失败
- 控制指令发送成功但系统状态未确认
- 当前播放器不在支持名单中
- 权限不足

### 8.3 降级策略

- 元数据缺失时允许展示播放器 Logo 和默认占位文案
- seek 不可用时，进度条只读，不允许拖拽
- 上一首 / 下一首不可用时，按钮禁用或隐藏，不假装可点
- 权限不足时，引导用户去设置授权，而不是静默失败
- 当前播放器不受支持时，不阻断整个模块；允许继续显示“当前播放器暂未支持”

---

## 9. 已知风险

### 9.1 外部播放器内手动操作

如果用户直接在播放器窗口里做拖拽、暂停、切歌，本地时间轴可能需要等待下一轮校准才能完全同步。

### 9.2 元数据变化导致的 `trackKey` 误判

如果播放器在同一首音频上频繁刷新标题、专辑或时长，可能触发时间轴重建。

### 9.3 参数是经验值

当前方案中：

- `grace window`
- `seek tolerance`
- 各状态轮询频率

都属于工程经验值，不同播放器版本下可能还要微调。

### 9.4 服务端轮询仍偏重

正式产品阶段不建议直接复用当前 Demo 的高频状态构建方式。

### 9.5 Apple Music 与 Spotify 仍未完成验证

这两者属于产品目标范围，但在完成实测前不得写成已支持。

---

## 10. 推荐落地方式

在后续正式产品中，建议沿用下面的分层：

- `播放器适配层`：负责发现、启动、控制、能力矩阵
- `会话状态层`：负责当前活跃播放器与元数据归一化
- `本地时间轴层`：负责 canonical timeline
- `模块状态层`：负责空态、折叠态、展开态、失败态
- `UI 层`：只消费统一状态，不直接信任系统时间值，也不直接写播放器差异逻辑

这样做的好处是：

- 能把“第三方播放器时间源不稳定”限制在底层
- 能把“不同播放器支持程度不同”限制在适配层
- 上层刘海面板 UI 可以保持平滑和一致
- 空态、折叠态、播放态、暂停态都能有明确边界
- 后续替换播放器 adapter 或权限策略时，不需要重写整个音乐模块

---

## 11. 当前建议

当前建议正式采用：

- `方案二` 作为默认技术路线
- `方案一` 保留为对照与回退方案
- 正式实现以“完整音乐模块方案”为准，而不是只实现“时间同步方案”

下一步优先级建议：

1. 把播放器能力矩阵固化到代码结构中
2. 把空态启动入口和折叠态状态流纳入实现范围
3. 为 `idle / collapsed / expanded / recovering` 建立分状态轮询调度
4. 补充 Apple Music 与 Spotify 的接入验证
5. 补充权限失败、未安装、不可控播放器的 UI 降级流程

一句话总结：

`音乐控制可以继续走；时间同步不要再信单一系统时间源，但正式产品不能只做时间同步，必须把播放器能力、模块状态、能耗策略和失败路径一起收进方案。`
