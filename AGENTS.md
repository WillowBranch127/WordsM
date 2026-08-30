# WordsM — Agent Context Document

## 项目概述

**WordsM** 是一个用 Swift/SwiftUI 开发的辅助背单词 iOS/macOS app。
支持 macOS（固定窗口）和 iOS（iPhone/iPad）双端运行。
目前主界面、数据层、设置界面、探索模式、复习模式、错题本模式均已实现。

### 多平台架构
- **macOS Target**：`WordsM/` 目录下的 SwiftUI 文件 + `WordsMApp.swift`（@main）
- **iOS Target**：`WordsM iOS/` 目录下的 iOS 专属文件 + `iOSApp.swift`（@main）
- **共享代码**：`ContentView.swift`、`ReviewView.swift`、`ExploreView.swift`、`SettingsView.swift`、`WordsManager.swift` 通过 Xcode 的 file system synchronized groups 同时加入两个 target
- **平台区分**：使用 `#if os(iOS)` / `#if !os(iOS)` 条件编译适配两端差异

---

## 核心功能设计

### 主页面
三个功能入口按钮：
1. **探索模式** — 随机浏览单词库
2. **复习模式** — 对已学单词进行主动回忆测试
3. **错题本** — 复习已标记的错误单词

每个子模式通过 `NavigationLink` 导航，返回主页使用回到根视图的方式。

---

### 探索模式

- 从 `words.json` 中随机抽选一个**未被学过**的单词
- 显示该单词的所有信息（单词、音标、词性、中文释义）
- **"记住了，下一个"** 按钮：
  - 调用 `WordsManager.markAsLearned(id)` 将该单词 ID 写入 `learned.json`
  - 再随机抽取下一个未学单词
- 所有单词学完后显示"已全部学完"提示页

**重要约束**：探索模式只展示未学过的单词，避免重复。

---

### 复习模式

从 `learned.json` 中的已学单词里随机抽词，随机选择出题方向。

#### 随机选词算法（洗牌式）

采用"一轮一消耗"的洗牌随机，类似音乐播放器的随机播放：
- `ReviewViewModel` 内维护 `shuffleQueue: [Int]` 和 `lastRoundOrder: [Int]`
- 每轮开始时执行 `ids.shuffled()` 打乱所有可用 ID
- 每次调用 `loadNextWord()` 时从队首 `removeFirst()` 真正消耗一个词
- 队列耗尽后自动开启新一轮，并通过 `repeat-while` 确保新轮顺序与上一轮不同（词数 > 1 时）
- 相邻两次题目不会出现同一单词（一轮内天然保证，跨轮通过顺序不同间接保证）
- 只有一个词时允许每轮相同
- 每次重新进入复习/错题本页面时 `shuffleQueue` 重置为空，重新开始新一轮

#### 方向一：看中文 → 写英文
- 显示：中文释义 + 词性
- 输入框下方画下划线（数量 = 英文单词字母数）
- **"不知道"** 按钮 → 显示完整单词信息，将该单词写入 `mistakes.json`，出现"下一个"按钮
- 用户提交后：
  - **正确** → 提示正确，显示"下一个"按钮
  - **错误** → 提示错误，显示完整单词信息，出现两个按钮：
    - **"加入错题本"** → 写入 `mistakes.json`，再显示"下一个"
    - **"下一个"** → 不加入错题本，直接下一题

#### 方向二：看英文 → 写中文
- 显示：英文单词
- 输入框供用户填写中文
- **"不知道"** 按钮 → 逻辑同上，写入 `mistakes.json`，显示"下一个"
- 用户提交后，调用用户配置的 AI API（OpenAI 兼容格式）判断答案合理性
  - AI 返回"合理值"作为参考展示给用户
  - 显示两个按钮："加入错题本" / "下一个"
- 网络失败时的 fallback 行为：待定，可在实现时决定

---

### 错题本模式（两轮大循环）

错题本采用**"两轮为一个大循环"**的机制，与复习模式完全不同。

#### 状态机设计

使用 `MistakeCyclePhase` 枚举精确表示当前阶段：
```swift
private enum MistakeCyclePhase {
    case notStarted   // 新大循环尚未开始第一轮
    case first        // 正在进行第一轮
    case second       // 正在进行第二轮
    case finished     // 两轮全部完成
}
```

`mistakePhase` 始终表示"当前正在进行的轮次"，不在建队时提前切换。

#### 核心流程

```
进入错题本
    ↓
mistakePhase = .notStarted
    ↓
建立第一轮：
  - 读取当前 manager.mistakeIDs
  - 为每个 ID 独立随机分配方向 → firstRoundDirections[id] = direction
  - 洗牌得到顺序 → mistakeShuffledIDs
  - mistakePhase = .first
    ↓
逐题答题（方向来自 firstRoundDirections）
    ↓
第一轮队列耗尽（mistakeShuffledIDs 空）
    ↓
建立第二轮：
  - 重新读取当前 manager.mistakeIDs（过滤中途移出的单词）
  - 只保留 firstRoundDirections 中有记录的 ID
  - 洗牌得到新顺序
  - mistakePhase = .second
    ↓
逐题答题（方向 = oppositeDirection(firstRoundDirections[id])）
    ↓
第二轮队列耗尽
    ↓
mistakePhase = .finished
isMistakeCycleFinished = true
    ↓
显示完成页面："你已刷完一次错题本啦！"
    ├── 再来一轮 → restartMistakeCycle() → 新建大循环
    └── 退出 → dismiss() → 返回主界面
```

#### 关键规则

1. **第一轮每个单词独立随机方向**：A→cnToEn, B→enToCn, C→cnToEn...
2. **第二轮方向强制取反**：A→enToCn, B→cnToEn, C→enToCn...
3. **两轮顺序独立随机**：第一轮可能是 [A,B,C,D]，第二轮可能是 [D,A,C,B]
4. **中途移出处理**：用户点击"移出错题本"后，该单词从后续出题队列中剔除，但不影响其他单词的方向记录
5. **方向记录贯穿整个大循环**：`firstRoundDirections` 在大循环期间保持不变，即使单词被移出也不重新随机
6. **完成判断**：只有两轮都完成后才显示完成页面，不允许提前结束
7. **重来一轮**：完全重置状态（mistakePhase=.notStarted, firstRoundDirections=[]），重新随机方向和顺序

---

## 数据存储

所有持久化数据存储在 app 的沙盒 Documents 目录中（`FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)`）。

| 数据 | 存储方式 | 说明 |
|------|------|------|
| 词库 `words.json` | 打包内置（Bundle） | 读取，不修改 |
| 已学 ID 列表 `learned.json` | Documents 目录 JSON 文件 | 仅存整数 ID 数组 |
| 错题 ID 列表 `mistakes.json` | Documents 目录 JSON 文件 | 仅存整数 ID 数组 |
| AI 配置（Base URL + API Key） | `UserDefaults` | 键名 `wordsM_baseURL`、`wordsM_apiKey`，字段变更时自动保存 |

使用 ID 而非字符串的原因：
- 避免同音词/近义词歧义
- 词库更新时（修正拼写）已学记录不受影响
- 复习时按 ID 反查完整单词信息

---

## 词库数据

### words.json
- 位置：`WordsM/words.json`（内置于 Bundle）
- 来源：`WordsM/words.csv`（3686 行，UTF-8 with BOM）
- 每条目结构：
  ```json
  {
    "id": 1,
    "word": "a",
    "phonetic": "ə; eɪ",
    "pos": "art.",
    "meaning": "①一个 ②任何，每一个"
  }
  ```
- `id`：从 1 开始的连续整数
- 词性共 26 种，常见：`n.`(1979), `a.`(573), `v.`(281), `vt.`(214), `ad.`(120)

### 词库更新
修改 `words.csv` 后运行：
```bash
python3 WordsM/convert_csv_to_json.py
```
脚本位于 `WordsM/convert_csv_to_json.py`，输出 `WordsM/words.json`。

---

## 架构与实现

### 文件结构
```
WordsM/                          # macOS + iOS 共享代码
├── WordsMApp.swift              # macOS @main 入口，含 Settings Scene（⌘,）
├── iOSApp.swift                 # iOS @main 入口
├── ContentView.swift            # 主界面：标题 + 三按钮 + 底部统计 + iOS 齿轮按钮
├── WordsManager.swift           # 数据层：加载词库，读写 learned/mistakes
├── ExploreView.swift            # 探索模式：展示单词 + "记住了，下一个"
├── ReviewView.swift             # 复习模式 + 错题本：两轮大循环 + AI 判断
├── SettingsView.swift           # 设置界面：AI 配置，onChange 自动保存
├── words.json                   # 内置词库（3686 词，iOS 需手动加入 Bundle）
└── words.csv                    # 原始词库（CSV 格式，UTF-8 BOM）

WordsM iOS/                      # iOS 专属文件
├── AppDelegate.swift            # UIApplicationDelegate（无 @main）
├── SceneDelegate.swift          # UIWindowScene 代理（简化版）
├── Info.plist                   # iOS 应用配置（纯 SwiftUI，无 storyboard）
└── Assets.xcassets/             # iOS 资源
```


#### ReviewView 架构
- `ReviewMode`：`learned` / `mistakes`，通过 `init(mode:manager:)` 传入
- `QuizDirection`：`cnToEn` / `enToCn`，每次换题随机分配
- `QuizState`：`idle` → `showingAnswer` → `checking` → `result` → `idle`（循环）
- `ReviewViewModel`：`ObservableObject`，持有答题状态和数据操作，**所有错题操作在 ViewModel 层统一处理**
- `QuizCard`：纯展示组件，通过闭包接收父层回调，不持有数据

#### 答题流程（汉译英 cnToEn）
1. 显示中文释义 + 词性（大字体）
2. 验证码式格子输入框（每格对应字母，自定义蓝色光标和下划线）
3. 用户输入后按 Enter 或点"提交" → `state = .checking`（显示 ProgressView 0.5s）
4. 精确字符串比较（case-insensitive）判断对错
5. 答错 → `manager.addToMistakes(word.id)` 自动加入错题本 → `state = .result`
6. 显示正确/错误反馈 + "下一个"按钮（支持 Enter 继续）

#### 答题流程（英译汉 enToCn）
1. 显示英文单词（超大字体）+ 音标
2. 单行居中 TextEditor，无框样式，height 72pt，placeholder "输入中文释义…"
3. 用户输入后按 Enter 或点"提交" → `state = .checking`
4. 调用 AI（OpenAI 兼容格式）判断中文释义合理性：
   - System prompt：明确判定标准和规则（多义词、口语化、义项顺序等）
   - User prompt：结构化输入 word.word / word.pos / word.meaning / userInput
   - 响应解析：优先 JSONDecoder，降级扫描 isReasonable 字段容错
5. fallback（未配置 AI / 网络失败）：关键词交集匹配（输入词与释义分段后取交集）
6. 答错 → `manager.addToMistakes(word.id)` 自动加入错题本 → `state = .result`

#### 不知道按钮
- 调 `manager.addToMistakes(word.id)`（不跳题）
- `state = .showingAnswer`，显示完整单词信息
- 出现"下一个"按钮，用户手动点击继续

#### 错题本模式区别
- 答对时显示"移出错题本"按钮（仅手动点击才删除，不自动移除）
- 答错时不显示"加入错题本"按钮（已在错题本中），自动确保 ID 存在（幂等）
### WordsManager
- `ObservableObject`，由 `@StateObject` 在 App 入口创建并注入为 `environmentObject`
- `init()` 时从 Bundle 加载词库，从 Documents 目录加载 learned/mistakes JSON
- 提供 `randomUnlearnedWord()`、`randomLearnedWord()`、`randomMistakeWord()` 供各模式使用
- `addToMistakes(_:)` / `removeFromMistakes(_:)` 同步更新 `mistakes.json`
- `markAsLearned(_:)` 同步更新 `learned.json`

### 设置窗口
- 通过 `Settings {}` Scene 注册，macOS 自动在 App 菜单生成"Settings…"入口（⌘,）
- 关闭时自动保存，无需确认按钮
- AI 配置存储于 `UserDefaults`，键名固定为 `wordsM_baseURL` 和 `wordsM_apiKey`

### 窗口规范
- **macOS**：主窗口使用 `.windowStyle(.hiddenTitleBar)` 隐藏系统标题栏，`.windowToolbarStyle(.unified)` 启用统一工具栏样式，固定尺寸：min 440×480，max 520×560
- **iOS**：全屏自适应，无固定尺寸约束；主界面右上角齿轮按钮进入设置页；探索/复习/错题本均通过 NavigationStack 导航

### iOS 适配要点
- 所有固定 `frame(minWidth:maxWidth:minHeight:maxHeight:)` 用 `#if !os(iOS)` 保护
- 字体大小使用 `.title`、`.title2`、`.body` 等语义化字体，配合 `lineLimit` 和 `minimumScaleFactor` 防止溢出
- 验证码输入框格子宽度根据屏幕宽度动态计算（`UIScreen.main.bounds.width`）
- 按钮宽度使用 `frame(maxWidth: .infinity)` 全宽适配
- 平台特定代码使用 `#if os(iOS)` / `#if !os(iOS)` 条件编译，避免在 modifier 链中嵌套 `#if`

---

## 开发约定

- **严格遵守 AGENTS.md**：实现功能时严格遵循本文档描述，禁止自行添加、修改或扩展功能范围；如需变更，先更新 AGENTS.md 并获得确认后再开发。
- **语言**：Swift / SwiftUI
- **平台**：iOS / macOS（双端适配，代码共用）
- **Swift 版本**：6.0（项目 pbxproj 中 SWIFT_VERSION = 6.0）
- **数据存储**：文件系统（JSON），非 Core Data
- **分支前缀**：`codex/`
- **平台适配**：iOS 专属代码用 `#if os(iOS)` 包裹，macOS 专属用 `#if !os(iOS)`；避免在 SwiftUI modifier 链中嵌套 `#if`，优先使用 computed property
- **状态机设计**：错题本两轮循环使用 `MistakeCyclePhase` 枚举，确保 `mistakePhase` 始终表示"当前阶段"而非"下一阶段"

---

## 开发进度

- [x] 数据层：`WordsManager`（词库加载、learned/mistakes 读写、随机抽词、addToMistakes/removeFromMistakes）
- [x] 主界面：三按钮布局 + 底部统计（已学/错题数量），iOS 右上角齿轮按钮
- [x] 探索模式：随机展示未学单词，"记住了，下一个"功能完整，iOS 响应式字体
- [x] 设置界面：AI 配置（Base URL、API Key、模型选择），onChange 自动保存，支持从 API 获取模型列表
- [x] 复习模式（汉译英）：完整实现，验证码式格子输入框，自定义蓝色光标，自动获取焦点
- [x] 复习模式（英译汉）：完整实现，单行居中 TextEditor，无框样式，placeholder 提示
- [x] 错题本模式：两轮大循环机制，第一轮随机方向+记录，第二轮强制取反，完成页面
- [x] 方向随机化：复习模式每次换题随机，错题本第一轮每个单词独立随机
- [x] AI 语义判断：OpenAI 兼容格式，结构化 prompt，容错解析（处理截断响应），fallback 关键词交集
- [x] 答题逻辑：答错自动加入错题本（ViewModel 层处理），"不知道"只加错题本不切题
- [x] 键盘支持：两个方向均支持 Enter 提交/下一步，结果页"下一个"按钮绑定 defaultAction
- [x] 数据同步：所有视图共享同一个 WordsManager 实例（init 参数注入，非单例）
- [x] 随机选词：复习模式洗牌式一轮一消耗，错题本两轮独立洗牌
- [x] iOS 适配：移除固定 frame，响应式字体/输入框宽度，键盘焦点恢复（direction/state 变化时）
- [x] 双端编译：`#if os(iOS)` / `#if !os(iOS)` 条件编译，macOS 和 iOS 均编译通过

---

## 已确认的设计决策

1. 词库统一使用 JSON 格式（不保留 CSV 作为运行时数据源）
2. 已学/错题文件仅存 ID 列表，不存完整对象
3. 探索模式不展示已学单词
4. 错题本中答对时出现"移出错题本"，仅当用户主动点击才移除
5. ID 使用连续整数（1-based），由转换脚本一次性生成，后续不变
6. AI 配置变更后即时生效，无需重启 app
