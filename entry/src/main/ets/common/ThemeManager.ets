// ThemeManager.ets - 主题管理器
// 管理应用的深色/浅色模式

import { AppearanceMode } from '../pages/SettingsPage';
import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 主题颜色定义
 */
export interface ThemeColors {
  // 背景色
  background: ResourceColor;
  cardBackground: ResourceColor;
  secondaryBackground: ResourceColor;
  
  // 文字颜色
  textPrimary: ResourceColor;
  textSecondary: ResourceColor;
  textTertiary: ResourceColor;
  
  // 分割线
  divider: ResourceColor;
  
  // 主色调
  primary: ResourceColor;
  primaryLight: ResourceColor;
  
  // 强调色
  accent: ResourceColor;
  accentLight: ResourceColor;
  
  // 状态色
  error: ResourceColor;
  success: ResourceColor;
  warning: ResourceColor;
  
  // 导航栏
  tabBarBackground: ResourceColor;
  tabBarActive: ResourceColor;
  tabBarInactive: ResourceColor;
  
  // 输入框
  inputBackground: ResourceColor;
  inputBorder: ResourceColor;
  placeholder: ResourceColor;
}

/**
 * 浅色主题
 */
export const LightTheme: ThemeColors = {
  background: '#F5F5F5',
  cardBackground: '#FFFFFF',
  secondaryBackground: '#FAFAFA',
  
  textPrimary: '#1A1A1A',
  textSecondary: '#666666',
  textTertiary: '#999999',
  
  divider: '#F0F0F0',
  
  primary: '#007DFF',
  primaryLight: 'rgba(0, 125, 255, 0.1)',
  
  accent: '#007DFF',
  accentLight: 'rgba(0, 125, 255, 0.1)',
  
  error: '#FF3B30',
  success: '#34C759',
  warning: '#FF9500',
  
  tabBarBackground: '#FFFFFF',
  tabBarActive: '#007DFF',
  tabBarInactive: '#999999',
  
  inputBackground: '#F5F5F5',
  inputBorder: '#E0E0E0',
  placeholder: '#CCCCCC'
};

/**
 * 深色主题
 */
export const DarkTheme: ThemeColors = {
  background: '#121212',
  cardBackground: '#1E1E1E',
  secondaryBackground: '#2A2A2A',
  
  textPrimary: '#FFFFFF',
  textSecondary: '#B3B3B3',
  textTertiary: '#808080',
  
  divider: '#333333',
  
  primary: '#0A84FF',
  primaryLight: 'rgba(10, 132, 255, 0.2)',
  
  accent: '#0A84FF',
  accentLight: 'rgba(10, 132, 255, 0.2)',
  
  error: '#FF453A',
  success: '#30D158',
  warning: '#FF9F0A',
  
  tabBarBackground: '#1E1E1E',
  tabBarActive: '#0A84FF',
  tabBarInactive: '#808080',
  
  inputBackground: '#2A2A2A',
  inputBorder: '#404040',
  placeholder: '#636366'
};

/**
 * 主题管理器 - 使用 AppStorage 实现全局状态
 */
@Observed
export class ThemeManager {
  private static instance: ThemeManager;
  
  private constructor() {}
  
  public static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }
  
  /**
   * 初始化主题存储
   */
  public static initializeStorage(): void {
    // 初始化 AppStorage 中的主题状态
    if (!AppStorage.has('isDarkMode')) {
      AppStorage.setOrCreate('isDarkMode', false);
    }
    if (!AppStorage.has('appearanceMode')) {
      AppStorage.setOrCreate('appearanceMode', AppearanceMode.SYSTEM);
    }
  }
  
  /**
   * 获取当前主题颜色
   */
  public static getColors(isDark: boolean): ThemeColors {
    return isDark ? DarkTheme : LightTheme;
  }
  
  /**
   * 更新主题模式
   */
  public static updateTheme(mode: AppearanceMode, systemColorMode?: ConfigurationConstant.ColorMode): void {
    let isDark = false;
    
    switch (mode) {
      case AppearanceMode.DARK:
        isDark = true;
        break;
      case AppearanceMode.LIGHT:
        isDark = false;
        break;
      case AppearanceMode.SYSTEM:
      default:
        // 跟随系统
        isDark = systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        break;
    }
    
    AppStorage.setOrCreate('isDarkMode', isDark);
    AppStorage.setOrCreate('appearanceMode', mode);
    console.info(`[ThemeManager] Theme updated: isDark=${isDark}, mode=${mode}`);
  }
  
  /**
   * 判断当前是否为深色模式
   */
  public static isDarkMode(): boolean {
    return AppStorage.get<boolean>('isDarkMode') ?? false;
  }
}

/**
 * 获取主题色的辅助函数
 */
export function getThemeColor(isDark: boolean, lightColor: ResourceColor, darkColor: ResourceColor): ResourceColor {
  return isDark ? darkColor : lightColor;
}
