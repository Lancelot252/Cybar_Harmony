// Index.ets - 主页面入口(底部导航栏架构)
// 对应 Swift 项目中的 ContentView.swift

import { RecipesPage } from './RecipesPage';
import { RecommendationsPage } from './RecommendationsPage';
import { CustomRecipePage } from './CustomRecipePage';
import { UserProfilePage } from './UserProfilePage';
import { ThemeManager, LightTheme, DarkTheme } from '../common/ThemeManager';
import { SettingsManager, AppearanceMode } from './SettingsPage';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

// 初始化主题存储
ThemeManager.initializeStorage();

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;
  @State userProfileRefreshTrigger: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  private settingsManager = SettingsManager.getInstance();
  
  aboutToAppear() {
    // 初始化设置管理器并加载主题
    this.initializeTheme();
  }
  
  private async initializeTheme() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.settingsManager.initialize(context);
      
      // 获取系统颜色模式
      const config = context.config;
      const systemColorMode = config.colorMode;
      
      // 应用主题
      ThemeManager.updateTheme(this.settingsManager.appearanceMode, systemColorMode);
    } catch (error) {
      console.error('[Index] 初始化主题失败:', error);
    }
  }
  
  // 获取当前主题色
  private getColors() {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  @Builder
  TabBuilder(index: number, title: string, icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([this.currentTabIndex === index ? this.getColors().tabBarActive : this.getColors().tabBarInactive])
      
      Text(title)
        .fontSize(10)
        .fontColor(this.currentTabIndex === index ? this.getColors().tabBarActive : this.getColors().tabBarInactive)
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  
  build() {
    Stack() {
      // 主 Tabs 导航
      Tabs({
        barPosition: BarPosition.End,
        index: this.currentTabIndex
      }) {
        // 推荐页
        TabContent() {
          RecommendationsPage()
        }
        .tabBar(this.TabBuilder(0, '推荐', $r('sys.symbol.star')))
        
        // 配方列表
        TabContent() {
          RecipesPage()
        }
        .tabBar(this.TabBuilder(1, '配方', $r('sys.symbol.list_bullet')))
        
        // 新配方
        TabContent() {
          CustomRecipePage()
        }
        .tabBar(this.TabBuilder(2, '新配方', $r('sys.symbol.plus_square')))
        
        // 用户中心
        TabContent() {
          UserProfilePage({ refreshTrigger: this.userProfileRefreshTrigger })
        }
        .tabBar(this.TabBuilder(3, '我的', $r('sys.symbol.person_square_fill')))
      }
      .onChange((index: number) => {
        this.currentTabIndex = index;
        if (index === 3) {
          this.userProfileRefreshTrigger++;
        }
      })
      .width('100%')
      .height('100%')
      .barMode(BarMode.Fixed)
      .barHeight(56)
      .barBackgroundColor(this.getColors().tabBarBackground)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
  }
}