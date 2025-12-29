# Cybar Harmony - AI 编程助手指南

## 项目概述

这是一个 **HarmonyOS Next** 鸡尾酒配方应用（Cybar），使用 **华为 ArkTS** 语言开发，目标 SDK 版本 5.0.0(12)。应用包含配方浏览、个性化推荐、自定义配方创建和用户管理功能。

> ⚠️ **重要**: 开发时必须严格遵循 [ArkTS 开发规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/introduction-to-arkts-V5)，ArkTS 是 TypeScript 的严格超集，禁止使用 `any`、动态属性访问等不安全特性。

## 架构核心

### 目录结构
```
entry/src/main/ets/
├── entryability/     # 应用入口 - EntryAbility 初始化全局服务
├── pages/            # UI 页面组件 (@Component/@Entry)
│   └── Index.ets     # 主入口 - 底部导航 Tabs 架构
├── services/         # APIService 单例 - 所有后端交互 + 观察者模式
├── models/           # TypeScript 接口定义 (Recipe, Ingredient, Comment 等)
└── common/           # ThemeManager - 深色/浅色主题系统
```

### 关键设计模式

1. **单例服务模式**: `APIService.getInstance()` 和 `SettingsManager.getInstance()` 管理全局状态
   - 在 `EntryAbility.onCreate()` 中调用 `initialize(context)` 初始化
   - APIService 统一管理 Cookie 认证、用户状态、偏好存储

2. **观察者模式**: APIService 使用 `addListener/removeListener` 通知 UI 状态变化
   - 登录/登出后调用 `notifyListeners()` 触发 UI 更新
   - 参考 `APIService.ets` 的 `StateChangeListener` 类型定义

3. **AppStorage 全局状态**: 通过装饰器实现跨组件响应式状态
   - `@StorageProp('isDarkMode')`: 单向绑定，页面读取主题
   - `@StorageLink('recipesRefreshTrigger')`: 双向绑定，跨页面刷新触发
   - `ThemeManager.initializeStorage()` 在应用启动时初始化

### 数据流与初始化顺序
```
EntryAbility.onCreate() 
  → APIService.initialize(context)    // 加载登录缓存、设置 Cookie
  → SettingsManager.initialize(context)  // 加载外观/语言设置
  → ThemeManager.updateTheme()        // 应用主题到 AppStorage

UI Page → APIService (单例) → HTTP 请求 (携带 Cookie) → 后端
                ↓
    preferences 持久化 (LOGIN_CACHE_KEY, app_settings)
```

## 代码规范

### ArkTS 组件结构（强制模式）
```typescript
// 页面组件标准结构 - 所有页面必须遵循此模式
@Entry  // 或 @Component（嵌套组件）
@Component
export struct XxxPage {
  // 1. 全局状态绑定（AppStorage）
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  // 2. 本地状态（@State 触发 UI 刷新）
  @State someData: DataType = initialValue;
  
  // 3. 主题色获取（必须实现）
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  // 4. 生命周期初始化
  aboutToAppear(): void {
    // 加载数据、订阅事件
  }
  
  aboutToDisappear(): void {
    // 清理监听器、资源释放
  }
  
  // 5. UI 构建
  build() {
    Column() {
      // 使用 this.getColors() 引用主题色
    }
    .backgroundColor(this.getColors().background)
  }
}
```

### 列表性能优化 - LazyForEach（长列表必备）
对于超过 10 条的列表，必须使用 `IDataSource` + `LazyForEach` 实现懒加载：

```typescript
// 1. 定义数据源类（参考 RecipesPage.ets）
class BasicDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: Recipe[] = [];
  
  public totalCount(): number { return this.originDataArray.length; }
  public getData(index: number): Recipe { return this.originDataArray[index]; }
  
  // 注册监听器
  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }
  
  // 通知数据变更
  public notifyDataReload(): void {
    this.listeners.forEach(listener => listener.onDataReloaded());
  }
  
  // 更新数据并通知
  public setData(data: Recipe[]) {
    this.originDataArray = data;
    this.notifyDataReload();
  }
}

// 2. 在组件中使用
@Component
export struct RecipesPage {
  @State recipesDataSource: BasicDataSource = new BasicDataSource();
  
  build() {
    List() {
      LazyForEach(this.recipesDataSource, (recipe: Recipe, index: number) => {
        ListItem() {
          // 每项 UI
        }
      }, (recipe: Recipe) => recipe.id) // 唯一 key
    }
  }
}
```

### 主题系统实现细节
- 颜色定义在 `ThemeManager.ets` (`LightTheme`/`DarkTheme`)
- 所有页面通过 `getColors()` 获取当前主题色（禁止硬编码颜色）
- 主题切换流程：
  ```typescript
  // SettingsPage.ets 中触发
  await this.settingsManager.setAppearanceMode(AppearanceMode.DARK);
  ThemeManager.updateTheme(mode, systemColorMode);
  // → AppStorage.setOrCreate('isDarkMode', true)
  // → 所有页面的 @StorageProp 自动响应
  ```
- 系统图标使用 `$r('sys.symbol.xxx')` (HarmonyOS 系统图标库)

### API 调用模式（Cookie 认证关键）
```typescript
// 使用 @kit.NetworkKit 的 http 模块
import { http } from '@kit.NetworkKit';

// 请求需要带 Cookie 认证（APIService 自动处理）
const options: http.HttpRequestOptions = {
  method: http.RequestMethod.GET,
  header: { 'Cookie': this.authCookie },  // 登录后自动设置
  readTimeout: 30000,
  connectTimeout: 30000
};
const response = await http.createHttp().request(url, options);

// 响应处理（需类型转换）
if (response.responseCode === 200) {
  const data: ESObject = response.result as ESObject;
  const username: string = Reflect.get(data, 'username') as string;
}
```

## 后端 API 端点

| 功能 | 端点 | 认证 | 说明 |
|------|------|------|------|
| 配方列表 | `GET /api/recipes?page=&limit=` | 否 | 支持 sortBy 参数 (default/likes/favorites/name) |
| 配方详情 | `GET /api/recipes/:id` | 否 | 返回详细配方（包含 ingredients 数组） |
| 点赞/收藏 | `POST /api/recipes/:id/like` | 是 | body: `{ action: 'like/unlike/favorite/unfavorite' }` |
| 评论列表 | `GET /api/recipes/:id/comments` | 否 | 返回所有评论 |
| 发表评论 | `POST /api/recipes/:id/comments` | 是 | body: `{ commentText: string }` |
| AI 生成配方 | `POST /api/ai/recipe` | 是 | body: `{ ingredients: string[], preferences: {} }` |
| 登录 | `POST /api/login` | 否 | body: `{ username, password }`，返回 Set-Cookie |
| 注册 | `POST /api/register` | 否 | body: `{ username, password, email }` |
| 认证状态 | `GET /api/auth/status` | 否 | 检查 Cookie 有效性 |
| 管理员统计 | `GET /api/admin/stats` | 是(Admin) | 返回 `{ totalUsers, totalRecipes }` |

**环境配置**（在 `APIService.ets` 顶部切换）：
```typescript
// 开发环境
const BASE_URL: string = 'http://10.0.2.2:80';  // Android 模拟器访问主机

// 生产环境
const BASE_URL: string = 'http://47.101.11.98:8080';
```

## 开发工作流

### 构建与调试
- 使用 **DevEco Studio** 进行开发和调试
- 构建工具: **hvigor** (类似 Gradle)
- 模拟器/真机调试时确保已授予 `ohos.permission.INTERNET` 权限

### 环境切换
在 `APIService.ets` 中切换后端地址：
```typescript
// 开发环境
// const BASE_URL: string = 'http://10.0.2.2:80';

// 生产环境
const BASE_URL: string = 'http://47.101.11.98:8080';
```

### 新增页面
1. 在 `pages/` 创建 `.ets` 文件
2. 在 `resources/base/profile/main_pages.json` 注册路由
3. 使用 `router.pushUrl({ url: 'pages/XxxPage', params: {} })` 导航

## 注意事项

### ArkTS 语言约束（必须遵守）
- **禁止 `any` 类型**: 使用 `ESObject` 处理动态 JSON 数据，配合 `Reflect.get()` 访问属性
- **禁止动态属性**: 不能使用 `obj[key]` 或 `obj.dynamicProp`，必须通过接口定义类型
- **显式类型声明**: 变量、参数、返回值都需要明确类型
- **禁止 `as` 断言绕过检查**: 类型转换需通过类型守卫或 `Reflect` API
- **数组遍历**: 使用 `forEach` / `for` 循环，避免 `for...in`

```typescript
// ❌ 错误写法
const data: any = response.result;
const name = data.name;

// ✅ 正确写法
const data: ESObject = response.result as ESObject;
const name: string = Reflect.get(data, 'name') as string;
```

### 其他开发规范
- **异步处理**: 使用 `async/await`，错误用 `try/catch` 包裹
- **乐观更新**: 点赞/收藏等交互先更新 UI，失败后回滚
- **资源引用**: 使用 `$r('app.media.xxx')` 或 `$r('sys.symbol.xxx')` 引用资源
- **状态管理**: 使用 `@State`、`@Prop`、`@Link`、`@StorageProp` 等装饰器
