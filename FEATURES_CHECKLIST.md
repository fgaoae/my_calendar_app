# 📋 功能完整性清单

> **目的：** UI 美化期间防止功能丢失  
> **更新时间：** 2026-04-21  
> **代码版本：** Phase 2 拆分完成后

---

## 📅 日历视图（CalendarViewWidget）功能清单

### 核心显示功能
- ✅ **Syncfusion Calendar 集成**
  - 支持多种视图：月视图、周视图、日视图、时间线视图
  - 周视图为默认启动视图
  - 视图切换器在顶部导航栏

- ✅ **时间导航**
  - 上一周/日期选择器/下一周按钮
  - "今天" 快速定位按钮
  - 显示当前展示日期（YYYY-MM-DD 格式）

- ✅ **左侧数据库事件列表**
  - 按数据库分组显示事件
  - 可扩展/收起数据库分组（ExpansionTile）
  - 每个分组显示事件数量
  - 事件项显示：名称、开始时间（HH:mm 格式）

### 事件编辑功能
- ✅ **点击事件打开编辑对话框**
  - 标题字段（可编辑）
  - 描述字段（可编辑）
  - 开始时间选择器（日期+时间）
  - 结束时间选择器（日期+时间，不能早于开始时间）
  - 提醒设置（不提醒/5分钟/15分钟/1小时）
  - 重复设置（不重复/每天/每周/每月）
    - 重复开始日期选择
    - 重复截止日期选择（可选，永久）
    - 生成 RRULE 字符串存储

### 事件属性系统
- ✅ **自定义属性编辑**
  - 文本属性：直接输入
  - 复选框属性：勾选/取消
  - 标签属性：从下拉列表选择或"不设置"
  - 标签选择界面显示：
    - 当前选中标签用深紫色高亮 + 勾选符号
    - "不设置" 选项用灰色显示

### 拖拽功能
- ✅ **左侧事件拖拽到日历**
  - Draggable 包装器，显示拖拽反馈 UI
  - DragTarget 接收，计算目标时间
  - 支持追踪多个指针位置（主要在目标区、次要在 DragTarget、三级任意位置）
  - 掉落后自动更新事件的 start_time 和 end_time
  - 计算持续时间，保持掉落前后的时长一致
  - 月视图掉落默认时间为 9:00 AM

- ✅ **日历内事件拖拽移动**
  - allowDragAndDrop: true
  - onDragEnd 回调处理
  - 移动后立即更新数据库

- ✅ **日历内事件时长调整**
  - allowAppointmentResize: true
  - onAppointmentResizeEnd 回调处理
  - 可调整开始时间和结束时间

### 事件创建功能
- ✅ **长按日历空白区域创建隐藏事件**
  - 自动创建或获取 `__HIDDEN__` 数据库
  - 在目标日期创建未命名事件
  - 隐藏数据库不显示在数据库视图
  - 成功后显示提示：已添加到隐藏数据库

### 事件删除功能
- ✅ **删除对话框**
  - 单击删除按钮打开确认对话框
  - 重复事件删除选项：
    - "仅本次"：添加异常日期（_sys_exdates）
    - "删除所有"：直接删除整个事件
  - 取消/删除按钮

### 数据同步机制
- ✅ **Supabase 实时流监听**
  - Stream 订阅 'events' 表（按 sort_order 排序）
  - Stream 订阅 'databases' 表（按 created_at 排序）
  - 监听外部更改（从数据库视图修改时）

- ✅ **跨视图同步**
  - MainScreen 管理 ValueNotifier<int> _syncTick
  - 日历视图监听 _syncTick 变化
  - 修改后调用 requestSync() 触发增量刷新
  - 100ms 防抖延迟，防止级联更新

- ✅ **乐观更新**
  - 修改前先更新本地 _allEvents 列表
  - setState 立即刷新 UI
  - 并行 await 数据库写入，失败时调用 _hardRefreshEvents() 回滚

### 数据库属性映射
- ✅ **Syncfusion Appointment 生成**
  - 从 _allEvents 构建 Appointment 列表
  - 映射 id → appointment.id
  - 映射 title / description / start_time / end_time
  - 映射 _sys_rrule 为 recurrenceRule
  - 映射 _sys_exdates 为 recurrenceExceptionDates（UTC 时间）

### 顶部导航栏功能
- ✅ **日期导航按钮**
  - 左箭头：后退一周（或月，根据当前视图）
  - 右箭头：前进一周（或月）
  - 中间"今天"按钮：跳转到当前日期

- ✅ **视图切换器**
  - 下拉菜单，选项：月、周、日、时间线
  - 切换时保持 displayDate

---

## 📊 数据库视图（DatabaseViewWidget）功能清单

### 数据库管理
- ✅ **创建数据库**
  - "新建数据库" 按钮在左侧导航
  - 弹窗输入数据库名称
  - 自动创建 schema=[], property_types={}, tag_options={}

- ✅ **重命名数据库**
  - 右键菜单 → "重命名"
  - 弹窗输入新名称
  - 立即更新本地列表和 UI

- ✅ **删除数据库**
  - 右键菜单 → "删除"
  - 确认对话框
  - 级联删除该数据库下所有事件
  - 如果删除的是当前选中数据库，自动切换到其他数据库

- ✅ **数据库列表导航**
  - 左侧列表显示所有非隐藏数据库
  - 当前选中数据库高亮背景色
  - 点击切换选中数据库

### 事件行管理
- ✅ **事件表格显示**
  - 列：复选框、拖拽手柄、名称、开始时间、结束时间、重复、提醒、自定义属性、删除按钮
  - 行颜色交替（白色/浅灰）
  - 水平滚动支持

- ✅ **事件行编辑**
  - 名称：直接点击编辑，弹窗输入
  - 开始时间：点击打开日期时间选择器
  - 结束时间：点击打开日期时间选择器（验证不早于开始时间）
  - 提醒：点击弹窗选择
  - 重复：点击弹窗设置重复规则
  - 自定义属性：根据类型调用对应编辑方法

### 属性管理系统
- ✅ **属性创建**
  - 表头最右端 "+" 按钮
  - 弹窗输入属性名称
  - 选择类型：文本/复选框/标签
  - 如果选择标签类型，支持添加/删除标签选项
  - 保存后更新 schema、property_types、tag_options

- ✅ **标签属性特殊编辑**
  - 表头右侧显示"编辑"图标（仅限标签类型）
  - 点击打开标签管理对话框
  - 添加新标签/删除现有标签
  - 保存到 tag_options

- ✅ **属性删除**
  - 表头右侧显示"X"按钮
  - 确认对话框
  - 删除 schema、property_types、tag_options 中的条目
  - 级联删除所有行中该属性的值

### 自定义属性编辑
- ✅ **文本属性**
  - 点击单元格打开编辑对话框
  - 输入框编辑
  - 清空内容则删除属性

- ✅ **复选框属性**
  - 单元格显示原生 Checkbox
  - 点击切换选中/取消
  - 立即保存到数据库

- ✅ **标签属性**
  - 单元格显示当前选中标签（深紫色背景药丸）
  - 点击打开标签选择对话框
  - 显示：所有可用标签、当前选中、"（不设置）" 选项
  - 选中后立即保存

### 行操作
- ✅ **新增行**
  - 表格底部 "新增一行" 按钮
  - 创建默认值：title='未命名', description='', start_time=null, end_time=null, properties={}
  - sort_order 自动递增
  - 新行立即添加到表格

- ✅ **删除行**
  - 行右侧删除按钮
  - 确认后删除该行

- ✅ **批量选择删除**
  - 每行前复选框，可多选
  - AppBar 显示 "删除选中(N)" 按钮
  - 选中后点击批量删除

- ✅ **行排序拖拽**
  - ReorderableListView 支持拖拽排序
  - 左侧拖拽手柄（IconButton）
  - 排序后自动更新数据库中每行的 sort_order

### 列宽管理
- ✅ **列宽拖拽调整**
  - 每列标题右侧有可拖拽边界
  - 拖拽调整列宽（范围 80-420）
  - 宽度存储在 _colWidths map

### 数据同步
- ✅ **Supabase 流监听**
  - Stream 订阅 'databases' 表（按 created_at 排序）
  - Stream 订阅 'events' 表（按 sort_order 排序）
  - 隐藏数据库自动过滤

- ✅ **跨视图同步**
  - 监听 syncTick ValueNotifier 变化
  - 100ms 防抖后调用 _fetchEventsNow()

- ✅ **乐观更新**
  - 编辑前先更新本地 _events 列表
  - setState 刷新 UI
  - 并行写入数据库，失败时调用 _fetchEventsNow() 回滚

### 操作反馈
- ✅ **重新加载**
  - AppBar 同步按钮
  - 调用 _reloadAll() 完全刷新

---

## 🔄 跨视图同步机制（MainScreen）

- ✅ **流共享**
  - 两个视图共享同一个 _sharedEventStream
  - 两个视图共享同一个 _sharedDbStream

- ✅ **同步信号**
  - ValueNotifier<int> _syncTick
  - 每次修改后调用 widget.requestSync() 触发 _requestDataSync()
  - 两个视图的 _syncListener 监听变化，防抖 100ms 后刷新

- ✅ **视图切换**
  - BottomNavigationBar 切换两个视图（IndexedStack）
  - 维持两个视图的独立状态

---

## 🛠️ 工具类

### DateHelper (lib/utils/date_helpers.dart)
- ✅ `pickDateThenTime(context, initial)` - 打开日期+时间选择器
- ✅ `pickDate(context, initial)` - 打开日期选择器
- ✅ `formatDate(datetime)` - 格式化为 YYYY-MM-DD
- ✅ `formatYmd(datetime)` - 格式化为 YYYY-MM-DD HH:mm
- ✅ `formatDateTime(value)` - 智能格式化显示
- ✅ `parseDateTime(string)` - 解析时间字符串
- ✅ `toUtcIso8601(datetime)` - 转换为 UTC ISO8601 字符串

### RRuleBuilder (lib/utils/rrule_builder.dart)
- ✅ `build()` - 生成 RRULE 字符串
  - 支持 DAILY, WEEKLY, MONTHLY 频率
  - WEEKLY 自动提取 BYDAY
  - MONTHLY 自动提取 BYMONTHDAY
  - 支持 UNTIL 日期限制（浮动时间，无 Z 后缀）
  - 返回格式：`FREQ=DAILY;INTERVAL=1;[BYDAY=...];[UNTIL=...]`

- ✅ `parse()` - 解析 RRULE 字符串
  - 返回元组：(frequency, until_date?, byday?)

---

## 🗄️ 数据模型

### Events 表（Supabase）
```
- id (uuid, PK)
- database_id (uuid, FK → databases.id)
- title (string)
- description (text)
- start_time (timestamptz, UTC)
- end_time (timestamptz, UTC)
- is_recurring (boolean)
- properties (jsonb)
  - _sys_rrule (string) - 重复规则
  - _sys_exdates (array) - 异常日期列表
  - _sys_repeat_start (string) - 重复开始日期
  - _sys_repeat_end (string) - 重复截止日期
  - _sys_reminder (string) - 提醒设置
  - [custom properties...]
- sort_order (integer)
- created_at (timestamptz)
- updated_at (timestamptz)
```

### Databases 表（Supabase）
```
- id (uuid, PK)
- name (string)
- schema (array) - 属性名称列表
- property_types (jsonb) - {prop_name: "text"|"checkbox"|"tag"}
- tag_options (jsonb) - {prop_name: [tag1, tag2, ...]}
- created_at (timestamptz)
- updated_at (timestamptz)
```

### 特殊数据库
- `__HIDDEN__` - 长按日历创建的隐藏事件存储数据库
  - 不在数据库视图中显示
  - 不在数据库列表中显示
  - 通过 kHiddenDatabaseName 常量识别

---

## ⚙️ 核心配置

### 时间处理
- ✅ 所有 start_time / end_time 存储为 UTC
- ✅ 显示时自动转换为本地时间 (.toLocal())
- ✅ RRULE 中 UNTIL 使用浮动时间格式（无 Z），避免 Syncfusion 时区问题
- ✅ 异常日期存储为 ISO8601 UTC 格式

### 状态管理
- ✅ 每个视图独立管理本地 _events 和 _dbs 列表
- ✅ 支持乐观更新（先本地后远程）
- ✅ 流监听确保外部修改可见
- ✅ 防抖机制防止级联更新

### 默认值
- ✅ 事件默认时长：1 小时
- ✅ 月视图掉落时间：9:00 AM
- ✅ 周视图掉落时间：保持原始分钟数
- ✅ 重复开始日期：事件开始日期
- ✅ 重复频率：不重复 (NONE)

---

## 📝 UI 美化注意事项

### 保护的关键功能
1. **Syncfusion Calendar 集成** - 核心日历显示，勿删除或过度修改
2. **Stream 订阅和防抖机制** - 确保跨视图同步，勿破坏
3. **乐观更新流程** - 用户体验关键，勿跳过本地更新
4. **RRULE 处理** - 复杂的重复规则解析，勿修改格式
5. **UTC 时间转换** - 确保时区正确，勿改变存储格式
6. **标签属性系统** - 支持多类型属性，勿简化
7. **行排序逻辑** - ReorderableListView + sort_order，保持同步

### 可安全修改的部分
- 颜色、字体、间距、布局
- 对话框 UI 样式
- 表格列宽、单元格样式
- 导航栏外观
- 按钮样式和图标

### 测试点
- [ ] 日期时间选择器弹窗是否正常打开/关闭
- [ ] 拖拽功能是否正常（左侧事件→日历）
- [ ] 重复事件是否正确生成（RRULE）
- [ ] 跨视图修改是否同步
- [ ] 复选框属性是否立即保存
- [ ] 标签属性是否显示和编辑正确
- [ ] 行排序是否保存到数据库
- [ ] 隐藏数据库是否真的隐藏

---

**版本历史：**
- 2026-04-21：Phase 2 拆分完成，功能文档创建
