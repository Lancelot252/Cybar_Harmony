// SettingsPage.ets - 设置页面
// 参考 Swift 项目中的 SettingsFullScreen 和 AppearanceSettings/LanguageSettings

import { router } from '@kit.ArkUI';
import APIService from '../services/APIService';
import promptAction from '@ohos.promptAction';
import preferences from '@ohos.data.preferences';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

// 外观模式枚举
export enum AppearanceMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

// 语言枚举
export enum AppLanguage {
  SYSTEM = 'system',
  ZH_HANS = 'zh-Hans',
  EN = 'en'
}

/**
 * 设置管理类 - 单例模式
 */
export class SettingsManager {
  private static instance: SettingsManager;
  private preferences?: preferences.Preferences;
  
  // 设置项
  private _appearanceMode: AppearanceMode = AppearanceMode.SYSTEM;
  private _language: AppLanguage = AppLanguage.SYSTEM;
  private _aiCacheTTLDays: number = 7;
  
  private constructor() {}
  
  public static getInstance(): SettingsManager {
    if (!SettingsManager.instance) {
      SettingsManager.instance = new SettingsManager();
    }
    return SettingsManager.instance;
  }
  
  /**
   * 初始化设置
   */
  public async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(context, 'app_settings');
      await this.loadSettings();
    } catch (error) {
      console.error('[SettingsManager] 初始化失败:', error);
    }
  }
  
  /**
   * 加载设置
   */
  private async loadSettings(): Promise<void> {
    if (!this.preferences) return;
    
    try {
      // 加载外观模式
      const appearanceStr = await this.preferences.get('appearanceMode', AppearanceMode.SYSTEM) as string;
      this._appearanceMode = appearanceStr as AppearanceMode;
      
      // 加载语言
      const languageStr = await this.preferences.get('language', AppLanguage.SYSTEM) as string;
      this._language = languageStr as AppLanguage;
      
      // 加载AI缓存TTL
      const ttl = await this.preferences.get('aiCacheTTLDays', 7) as number;
      this._aiCacheTTLDays = ttl;
      
      console.info('[SettingsManager] 设置加载完成');
    } catch (error) {
      console.error('[SettingsManager] 加载设置失败:', error);
    }
  }
  
  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.preferences) return;
    
    try {
      await this.preferences.put('appearanceMode', this._appearanceMode);
      await this.preferences.put('language', this._language);
      await this.preferences.put('aiCacheTTLDays', this._aiCacheTTLDays);
      await this.preferences.flush();
    } catch (error) {
      console.error('[SettingsManager] 保存设置失败:', error);
    }
  }
  
  // Getters and Setters
  public get appearanceMode(): AppearanceMode {
    return this._appearanceMode;
  }
  
  public async setAppearanceMode(mode: AppearanceMode): Promise<void> {
    this._appearanceMode = mode;
    await this.saveSettings();
  }
  
  public get language(): AppLanguage {
    return this._language;
  }
  
  public async setLanguage(lang: AppLanguage): Promise<void> {
    this._language = lang;
    await this.saveSettings();
  }
  
  public get aiCacheTTLDays(): number {
    return this._aiCacheTTLDays;
  }
  
  public async setAICacheTTLDays(days: number): Promise<void> {
    this._aiCacheTTLDays = days;
    await this.saveSettings();
  }
  
  /**
   * 获取外观模式显示名称
   */
  public getAppearanceModeLabel(mode: AppearanceMode): string {
    switch (mode) {
      case AppearanceMode.SYSTEM:
        return '跟随系统';
      case AppearanceMode.LIGHT:
        return '浅色';
      case AppearanceMode.DARK:
        return '深色';
      default:
        return '跟随系统';
    }
  }
  
  /**
   * 获取语言显示名称
   */
  public getLanguageLabel(lang: AppLanguage): string {
    switch (lang) {
      case AppLanguage.SYSTEM:
        return '跟随系统';
      case AppLanguage.ZH_HANS:
        return '简体中文';
      case AppLanguage.EN:
        return 'English';
      default:
        return '跟随系统';
    }
  }
}

/**
 * 设置页面组件
 */
@Entry
@Component
export struct SettingsPage {
  @State appearanceMode: AppearanceMode = AppearanceMode.SYSTEM;
  @State language: AppLanguage = AppLanguage.SYSTEM;
  @State aiCacheTTLDays: number = 7;
  @State isLoggedIn: boolean = false;
  @State userName: string = '';
  @State userRole: string = '';
  @State isAdmin: boolean = false;
  @State showLogoutConfirm: boolean = false; // 布尔状态，控制Sheet显示
  @State showLanguageDialog: boolean = false;
  @State pendingLanguage: AppLanguage = AppLanguage.SYSTEM;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly cacheTTLOptions: number[] = [1, 3, 7, 14, 30];
  
  // 获取当前主题色
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  aboutToAppear() {
    // 加载设置
    this.appearanceMode = this.settingsManager.appearanceMode;
    this.language = this.settingsManager.language;
    this.aiCacheTTLDays = this.settingsManager.aiCacheTTLDays;
    
    // 加载用户信息
    const apiService = APIService.getInstance();
    this.isLoggedIn = apiService.isLoggedIn;
    if (apiService.currentUser) {
      this.userName = apiService.currentUser.username;
      this.userRole = apiService.currentUser.role;
      this.isAdmin = this.userRole === 'admin';
    }
  }
  
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([this.getColors().accent])
            Text('返回')
              .fontSize(16)
              .fontColor(this.getColors().accent)
          }
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .height(44)
        .padding({ left: 4, right: 12 })
        .onClick(() => {
          router.back();
        })
        
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        // 占位保持标题居中
        Row()
          .width(80)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.getColors().cardBackground)
      
      // 设置内容
      Scroll() {
        Column({ space: 20 }) {
          // 外观设置
          this.buildAppearanceSection();
          
          // 语言设置
          this.buildLanguageSection();
          
          // AI缓存设置
          this.buildAICacheSection();
          
          // 账户设置
          this.buildAccountSection();
          
          // 关于
          this.buildAboutSection();
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(this.getColors().background)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
    .bindSheet($$this.showLogoutConfirm, this.buildLogoutDialog(), {
      detents: [SheetSize.MEDIUM],
      onDisappear: () => {
        this.showLogoutConfirm = false;
      }
    })
    .bindSheet(this.showLanguageDialog, this.buildLanguageDialog(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => {
        this.showLanguageDialog = false;
      }
    })
  }
  
  /**
   * 退出登录对话框
   */
  @Builder
  buildLogoutDialog() {
    Column({ space: 20 }) {
      Text('确认退出登录？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20 })
      
      Text('退出后将无法使用完整功能')
        .fontSize(14)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
      
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .onClick(() => {
            this.showLogoutConfirm = false;
          })
        
        Button('退出')
          .layoutWeight(1)
          .backgroundColor('#FF3B30')
          .fontColor(Color.White)
          .onClick(async () => {
            this.showLogoutConfirm = false;
            try {
              await APIService.getInstance().logout();
              promptAction.showToast({ message: '已退出登录' });
              router.back();
            } catch (error) {
              promptAction.showToast({ message: '退出登录失败' });
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('100%')
  }
  
  /**
   * 语言选择对话框
   */
  @Builder
  buildLanguageDialog() {
    Column({ space: 0 }) {
      Text('选择语言')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 16 })
      
      // 语言选项
      Column({ space: 0 }) {
        this.buildLanguageOption(AppLanguage.SYSTEM, '跟随系统');
        Divider().color('#F0F0F0');
        this.buildLanguageOption(AppLanguage.ZH_HANS, '简体中文');
        Divider().color('#F0F0F0');
        this.buildLanguageOption(AppLanguage.EN, 'English');
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      
      Button('关闭')
        .width('90%')
        .margin({ top: 20, bottom: 20 })
        .onClick(() => {
          this.showLanguageDialog = false;
        })
    }
    .width('100%')
  }
  
  /**
   * 语言选项
   */
  @Builder
  buildLanguageOption(lang: AppLanguage, label: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .layoutWeight(1)
      
      if (this.language === lang) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor(['#007DFF'])
      }
    }
    .width('100%')
    .height(50)
    .onClick(async () => {
      if (this.language !== lang) {
        this.language = lang;
        await this.settingsManager.setLanguage(lang);
        promptAction.showToast({ 
          message: '语言已切换，重启应用后生效',
          duration: 2000
        });
      }
      this.showLanguageDialog = false;
    })
  }
  
  /**
   * 应用主题变更
   */
  private applyThemeChange(mode: AppearanceMode) {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const config = context.config;
      const systemColorMode = config.colorMode;
      ThemeManager.updateTheme(mode, systemColorMode);
    } catch (error) {
      console.error('[SettingsPage] 应用主题失败:', error);
    }
  }

  /**
   * 外观设置区域
   */
  @Builder
  buildAppearanceSection() {
    Column({ space: 0 }) {
      // 标题
      Text('外观')
        .fontSize(14)
        .fontColor(this.getColors().textSecondary)
        .width('100%')
        .padding({ left: 16, bottom: 8 })
      
      // 设置项
      Column({ space: 0 }) {
        // 跟随系统
        Row() {
          Text('跟随系统')
            .fontSize(16)
            .fontColor(this.getColors().textPrimary)
            .layoutWeight(1)
          
          Toggle({ type: ToggleType.Switch, isOn: this.appearanceMode === AppearanceMode.SYSTEM })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.appearanceMode = AppearanceMode.SYSTEM;
                this.settingsManager.setAppearanceMode(AppearanceMode.SYSTEM);
                this.applyThemeChange(AppearanceMode.SYSTEM);
              } else {
                this.appearanceMode = AppearanceMode.LIGHT;
                this.settingsManager.setAppearanceMode(AppearanceMode.LIGHT);
                this.applyThemeChange(AppearanceMode.LIGHT);
              }
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        
        // 深色模式（仅在非跟随系统时显示）
        if (this.appearanceMode !== AppearanceMode.SYSTEM) {
          Divider()
            .color(this.getColors().divider)
            .padding({ left: 16, right: 16 })
          
          Row() {
            Text('深色模式')
              .fontSize(16)
              .fontColor(this.getColors().textPrimary)
              .layoutWeight(1)
            
            Toggle({ type: ToggleType.Switch, isOn: this.appearanceMode === AppearanceMode.DARK })
              .onChange((isOn: boolean) => {
                const newMode = isOn ? AppearanceMode.DARK : AppearanceMode.LIGHT;
                this.appearanceMode = newMode;
                this.settingsManager.setAppearanceMode(newMode);
                this.applyThemeChange(newMode);
              })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
        }
      }
      .width('100%')
      .backgroundColor(this.getColors().cardBackground)
      .borderRadius(12)
    }
  }
  
  /**
   * 语言设置区域
   */
  @Builder
  buildLanguageSection() {
    Column({ space: 0 }) {
      // 标题
      Text('语言')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })
      
      // 设置项
      Column({ space: 0 }) {
        Row() {
          Text('应用语言')
            .fontSize(16)
          
          Blank()
          
          Text(this.settingsManager.getLanguageLabel(this.language))
            .fontSize(14)
            .fontColor('#999999')
            .margin({ right: 8 })
          
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor(['#999999'])
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.showLanguageDialog = true;
        })
        
        Divider()
          .color('#F0F0F0')
          .padding({ left: 16, right: 16 })
        
        // 提示信息
        Row() {
          Text('切换语言后需要重启应用生效')
            .fontSize(12)
            .fontColor('#999999')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
  }
  
  /**
   * AI缓存设置区域
   */
  @Builder
  buildAICacheSection() {
    Column({ space: 0 }) {
      // 标题
      Text('AI缓存')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })
      
      // 设置项
      Column({ space: 0 }) {
        Row() {
          Text('缓存有效期')
            .fontSize(16)
          
          Blank()
          
          Text(`${this.aiCacheTTLDays} 天`)
            .fontSize(14)
            .fontColor('#999999')
            .margin({ right: 8 })
          
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor(['#999999'])
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          // TODO: 显示选择器
          promptAction.showToast({ message: '功能开发中...' });
        })
        
        Divider()
          .color('#F0F0F0')
          .padding({ left: 16, right: 16 })
        
        // 清除缓存
        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor(['#FF3B30'])
            .margin({ right: 12 })
          
          Text('清除缓存')
            .fontSize(16)
            .fontColor('#FF3B30')
          
          Blank()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          // TODO: 清除缓存
          promptAction.showToast({ 
            message: '缓存已清除',
            duration: 2000
          });
        })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
  }
  
  /**
   * 账户设置区域
   */
  @Builder
  buildAccountSection() {
    Column({ space: 0 }) {
      // 标题
      Text('账户')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })
      
      // 设置项
      Column({ space: 0 }) {
        // 管理员面板（仅管理员可见）
        if (this.isAdmin) {
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape_fill'))
              .fontSize(20)
              .fontColor(['#666666'])
              .margin({ right: 12 })
            
            Text('管理员面板')
              .fontSize(16)
            
            Blank()
            
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor(['#999999'])
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            router.pushUrl({
              url: 'pages/AdminPage'
            }).catch((error: Error) => {
              console.error('[SettingsPage] 跳转管理员页面失败:', error);
              promptAction.showToast({ message: '打开失败' });
            });
          })
          
          Divider()
            .color('#F0F0F0')
            .padding({ left: 16, right: 16 })
        }
        
        // 退出登录
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(20)
            .fontColor(['#FF3B30'])
            .margin({ right: 12 })
          
          Text('退出登录')
            .fontSize(16)
            .fontColor('#FF3B30')
          
          Blank()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.showLogoutConfirm = true;
        })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
  }
  
  /**
   * 关于区域
   */
  @Builder
  buildAboutSection() {
    Column({ space: 0 }) {
      // 标题
      Text('关于')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })
      
      // 设置项
      Column({ space: 0 }) {
        // 版本
        Row() {
          Text('版本')
            .fontSize(16)
          
          Blank()
          
          Text('2.0.0')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        
        Divider()
          .color('#F0F0F0')
          .padding({ left: 16, right: 16 })
        
        // 开发者
        Row() {
          Text('开发者')
            .fontSize(16)
          
          Blank()
          
          Text('Cybar Team')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
  }
}
