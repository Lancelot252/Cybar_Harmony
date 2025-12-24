# Cybar Harmony - AI 编程助手指南

## 项目概述

这是一个 **HarmonyOS Next** 鸡尾酒配方应用（Cybar），使用 **华为 ArkTS** 语言开发，目标 SDK 版本 5.0.0(12)。应用包含配方浏览、个性化推荐、自定义配方创建和用户管理功能。

> ⚠️ **重要**: 开发时必须严格遵循 [ArkTS 开发规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/introduction-to-arkts-V5)，ArkTS 是 TypeScript 的严格超集，禁止使用 `any`、动态属性访问等不安全特性。

## 架构核心

### 目录结构
```
entry/src/main/ets/
├── entryability/     # 应用入口，初始化 APIService 和 SettingsManager
├── pages/            # UI 页面组件 (@Component/@Entry)
├── services/         # APIService 单例 - 所有后端交互
├── models/           # TypeScript 接口定义 (Recipe, Ingredient, Comment 等)
└── common/           # ThemeManager - 深色/浅色主题系统
```

### 关键设计模式

1. **单例服务模式**: `APIService.getInstance()` 和 `SettingsManager.getInstance()` 管理全局状态
2. **观察者模式**: APIService 使用 `addListener/removeListener` 通知 UI 状态变化
3. **AppStorage 状态同步**: 通过 `@StorageProp('isDarkMode')` 实现跨组件主题同步

### 数据流
```
UI Page → APIService (单例) → HTTP 请求 → 后端 (47.101.11.98:8080)
                ↓
    preferences 持久化 (登录缓存、设置)
```

## 代码规范

### ArkTS 组件结构
```typescript
// 页面组件标准结构
@Component
export struct XxxPage {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State someData: DataType = initialValue;
  
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  aboutToAppear(): void {
    // 初始化逻辑，如加载数据
  }
  
  build() {
    // UI 构建
  }
}
```

### 列表性能优化 - LazyForEach
对于长列表，必须使用 `IDataSource` + `LazyForEach`：
```typescript
class BasicDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: Recipe[] = [];
  // 实现 totalCount, getData, registerDataChangeListener 等方法
}
```
参考: `RecipesPage.ets`, `RecommendationsPage.ets`

### 主题系统
- 颜色定义在 `ThemeManager.ets` (`LightTheme`/`DarkTheme`)
- 所有页面通过 `getColors()` 获取当前主题色
- 使用 `ResourceColor` 类型定义颜色

### API 调用模式
```typescript
// 使用 @kit.NetworkKit 的 http 模块
import { http } from '@kit.NetworkKit';

// 请求需要带 Cookie 认证
const options = this.createRequestOptions(http.RequestMethod.GET);
const response = await http.createHttp().request(url, options);
```

## 后端 API 端点

| 功能 | 端点 | 认证 |
|------|------|------|
| 配方列表 | `GET /api/recipes?page=&limit=` | 否 |
| 配方详情 | `GET /api/recipes/:id` | 否 |
| 点赞/收藏 | `POST /api/recipes/:id/like` | 是 |
| 评论 | `GET/POST /api/recipes/:id/comments` | 是(POST) |
| AI 生成配方 | `POST /api/ai/recipe` | 是 |
| 登录 | `POST /api/login` | 否 |
| 认证状态 | `GET /api/auth/status` | 否 |

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
