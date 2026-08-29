# WordsM — Agent Context Document

## 项目概述

**WordsM** 是一个用 Swift/SwiftUI 开发的辅助背单词 iOS/macOS app。
目前主界面、数据层、设置界面已实现，探索模式入口已就绪。

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

从 `learned.json` 中的已学单词里随机抽词，随机选择出题方向：

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

### 错题本模式

- 从 `mistakes.json` 中随机抽词
- 出题逻辑与复习模式完全一致
- 区别：
  - **不显示"加入错题本"按钮**（已在错题本中）
  - 用户**答对**时，除"下一个"外，额外显示**"移出错题本"**按钮
  - 只有用户点击"移出错题本"，才将该单词 ID 从 `mistakes.json` 中删除
  - 答错时仍只显示"下一个"

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
WordsM/
├── WordsMApp.swift        # @main 入口，挂载 WordsManager 到 environmentObject
├── ContentView.swift      # 主界面：标题 + 三按钮（探索/复习/错题本）+ 底部统计
├── WordsManager.swift     # 数据层：加载词库，读写 learned/mistakes，提供随机抽词方法
├── ExploreView.swift      # 探索模式：展示单词 + "记住了，下一个"按钮
├── ReviewView.swift       # 复习模式（待实现）：支持两种出题方向
├── SettingsView.swift     # 设置界面：AI Base URL + API Key，onChange 自动保存
├── words.json             # 内置词库（3686 词）
└── words.csv              # 原始词库（CSV 格式，UTF-8 BOM）
```

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
- 主窗口使用 `.windowStyle(.hiddenTitleBar)` 隐藏系统标题栏
- `.windowToolbarStyle(.unified)` 启用统一工具栏样式
- 主界面固定尺寸：min 440×480，max 520×560

---

## 开发约定

- **严格遵守 AGENTS.md**：实现功能时严格遵循本文档描述，禁止自行添加、修改或扩展功能范围；如需变更，先更新 AGENTS.md 并获得确认后再开发。
- **语言**：Swift / SwiftUI
- **平台**：iOS / macOS（统一 UI，当前优先 macOS）
- **Swift 版本**：6.0（项目 pbxproj 中 SWIFT_VERSION = 6.0）
- **数据存储**：文件系统（JSON），非 Core Data
- **分支前缀**：`codex/`

---

## 开发进度

- [x] 数据层：`WordsManager`（词库加载、learned/mistakes 读写、随机抽词）
- [x] 主界面：三按钮布局 + 底部统计（已学/错题数量）
- [x] 探索模式：随机展示未学单词，"记住了，下一个"功能完整
- [x] 设置界面：AI 配置，自动保存
- [ ] 复习模式：两种出题方向的完整实现
- [ ] 错题本模式：完整实现（含"移出错题本"逻辑）
- [ ] AI 语义判断：调用 OpenAI 兼容 API 评估中文答案合理性

---

## 已确认的设计决策

1. 词库统一使用 JSON 格式（不保留 CSV 作为运行时数据源）
2. 已学/错题文件仅存 ID 列表，不存完整对象
3. 探索模式不展示已学单词
4. 错题本中答对时出现"移出错题本"，仅当用户主动点击才移除
5. ID 使用连续整数（1-based），由转换脚本一次性生成，后续不变
6. AI 配置变更后即时生效，无需重启 app
