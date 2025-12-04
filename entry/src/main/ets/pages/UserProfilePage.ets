// UserProfilePage.ets - 用户中心页面
// 对应 Swift 项目中的 UserProfileView

import APIService from '../services/APIService';
import { LoginPage } from './LoginPage';
import { RegisterPage } from './RegisterPage';
import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

@Component
export struct UserProfilePage {
  // 从外部传入的刷新触发器
  @Prop @Watch('onRefreshTriggerChange') refreshTrigger: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  @State isLoggedIn: boolean = false;
  @State userName: string = '未登录';
  @State userRole: string = '';
  @State showLogin: boolean = false;
  @State showRegister: boolean = false;
  
  // 数据状态
  @State favoritesCount: number = 0;
  @State myRecipesCount: number = 0;
  @State totalLikes: number = 0;
  @State loadingFavorites: boolean = false;
  @State loadingMyRecipes: boolean = false;
  @State favoritesError: string = '';
  @State myRecipesError: string = '';
  @State loginStatusDebug: string = '';
  
  // 获取当前主题色
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  // 刷新触发器变化时刷新数据
  onRefreshTriggerChange() {
    console.info('[UserProfilePage] refreshTrigger changed, refreshing...');
    if (this.isLoggedIn) {
      this.refreshAll();
    }
  }
  
  // 状态变化监听器
  private stateChangeListener = () => {
    this.updateFromAPIService();
  }
  
  // 从 APIService 更新本地状态
  private updateFromAPIService() {
    const apiService = APIService.getInstance();
    const wasLoggedIn = this.isLoggedIn;
    this.isLoggedIn = apiService.isLoggedIn;
    
    if (apiService.currentUser) {
      this.userName = apiService.currentUser.username;
      this.userRole = apiService.currentUser.role;
    } else {
      this.userName = '未登录';
      this.userRole = '';
    }
    const cacheInfo = apiService.cachedLogin;
    
    // 如果从未登录变为已登录,刷新数据
    if (!wasLoggedIn && this.isLoggedIn) {
      this.refreshAll();
    }
    
    // 如果从已登录变为未登录,清空数据
    if (wasLoggedIn && !this.isLoggedIn) {
      this.clearData();
    }

    const timestamp = new Date().toLocaleString();
    const cacheLabel = cacheInfo ? `${cacheInfo.username}/${cacheInfo.role || '角色未知'}` : '无缓存';
    const cacheAge = cacheInfo ? `${Math.floor((Date.now() - cacheInfo.cachedAt) / (60 * 1000))}分钟` : 'N/A';
    // this.loginStatusDebug = `${timestamp}｜前状态 ${wasLoggedIn ? '已登录' : '未登录'} → 当前 ${this.isLoggedIn ? '已登录' : '未登录'}｜缓存 ${cacheLabel}｜缓存龄 ${cacheAge}`;
  }
  
  // 刷新所有数据
  private refreshAll() {
    this.totalLikes = 0;
    this.loadFavorites();
    this.loadMyRecipes();
  }
  
  // 清空数据
  private clearData() {
    this.favoritesCount = 0;
    this.myRecipesCount = 0;
    this.totalLikes = 0;
    this.favoritesError = '';
    this.myRecipesError = '';
  }
  
  // 加载收藏列表
  private async loadFavorites() {
    this.loadingFavorites = true;
    this.favoritesError = '';
    
    try {
      const favorites = await APIService.getInstance().fetchUserFavorites();
      this.favoritesCount = Array.isArray(favorites) ? favorites.length : 0;
    } catch (error) {
      this.favoritesError = error instanceof Error ? error.message : '加载失败';
    } finally {
      this.loadingFavorites = false;
    }
  }
  
  // 加载我的配方
  private async loadMyRecipes() {
    this.loadingMyRecipes = true;
    this.myRecipesError = '';
    
    try {
      const apiService = APIService.getInstance();
      const recipes = await apiService.fetchUserCreatedRecipes();
      this.myRecipesCount = Array.isArray(recipes) ? recipes.length : 0;
      
      // 计算总点赞数
      if (Array.isArray(recipes) && recipes.length > 0) {
        // 先尝试从返回数据中获取
        const initialLikes = recipes.reduce((sum: number, recipe: ESObject) => {
          const likeCount = recipe['likeCount'] as number || recipe['like_count'] as number || 0;
          return sum + likeCount;
        }, 0);
        
        this.totalLikes = initialLikes;
        
        // 如果所有配方的点赞数都是0,可能是服务器没有返回,需要补充
        if (initialLikes === 0) {
          console.info('[UserProfilePage] 补充配方点赞数统计...');
          let totalLikes = 0;
          
          // 批量获取每个配方的详情
          const promises = recipes.map(async (recipe: ESObject) => {
            try {
              const recipeId = recipe['id'] as string;
              const detail = await apiService.fetchRecipeDetail(recipeId);
              const likeCount = detail['likeCount'] as number || detail['like_count'] as number || 0;
              return likeCount;
            } catch (error) {
              console.warn('[UserProfilePage] 获取配方点赞数失败:', error);
              return 0;
            }
          });
          
          const likeCounts = await Promise.all(promises);
          totalLikes = likeCounts.reduce((sum, count) => sum + count, 0);
          this.totalLikes = totalLikes;
          console.info(`[UserProfilePage] 补充完成, 总点赞数: ${totalLikes}`);
        }
      } else {
        this.totalLikes = 0;
      }
    } catch (error) {
      this.myRecipesError = error instanceof Error ? error.message : '加载失败';
      this.totalLikes = 0;
    } finally {
      this.loadingMyRecipes = false;
    }
  }
  
  // 登出
  private async handleLogout() {
    try {
      await APIService.getInstance().logout();
      promptAction.showToast({ message: '已退出登录' });
    } catch (error) {
      promptAction.showToast({ message: '退出登录失败' });
    }
  }
  
  aboutToAppear() {
    // 初始化时更新状态
    this.updateFromAPIService();
    
    // 注册监听器
    APIService.getInstance().addListener(this.stateChangeListener);
    
    // 如果已登录,加载数据
    if (this.isLoggedIn) {
      this.refreshAll();
    }
  }
  
  aboutToDisappear() {
    // 移除监听器
    APIService.getInstance().removeListener(this.stateChangeListener);
  }
  
  // 每次页面显示时刷新数据（从其他页面返回时也会触发）
  onPageShow() {
    console.info('[UserProfilePage] onPageShow triggered');
    if (this.isLoggedIn) {
      this.refreshAll();
    }
  }
  
  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('我的')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.getColors().cardBackground)
        
        if (this.isLoggedIn) {
          // 已登录状态
          this.buildLoggedInView();
        } else {
          // 未登录状态
          this.buildLoginPromptView();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().background)
      
      // 登录弹窗
      if (this.showLogin) {
        Column() {
          LoginPage({
            onSuccess: () => {
              this.showLogin = false;
              // 状态会通过监听器自动更新
            },
            onCancel: () => {
              this.showLogin = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.getColors().cardBackground)
        .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 1000 } })
        .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: 1000 } })
      }
      
      // 注册弹窗
      if (this.showRegister) {
        Column() {
          RegisterPage({
            onSuccess: () => {
              this.showRegister = false;
              // 状态会通过监听器自动更新
            },
            onCancel: () => {
              this.showRegister = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.getColors().cardBackground)
        .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 1000 } })
        .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: 1000 } })
      }
    }
    .width('100%')
    .height('100%')
  }
  
  // 未登录视图
  @Builder
  buildLoginPromptView() {
    Column() {
      Blank()
      
      Column({ space: 20 }) {
        // 图标
        SymbolGlyph($r('sys.symbol.person'))
          .fontSize(80)
          .fontColor([this.getColors().textTertiary])
        
        // 提示文字
        Text('登录以使用完整功能')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().textPrimary)
        
        Text('登录后可以收藏配方、创建配方等')
          .fontSize(14)
          .fontColor(this.getColors().textSecondary)
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })

        Text(this.loginStatusDebug)
          .fontSize(12)
          .fontColor(this.getColors().textTertiary)
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
        
        // 登录注册按钮
        Column({ space: 12 }) {
          Button('登录')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#007DFF')
            .borderRadius(12)
            .onClick(() => {
              this.showLogin = true;
            })
          
          Button('注册新账号')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.isDarkMode ? 'rgba(0, 125, 255, 0.2)' : 'rgba(0, 125, 255, 0.1)')
            .fontColor('#007DFF')
            .borderRadius(12)
            .onClick(() => {
              this.showRegister = true;
            })
        }
        .width('100%')
        .padding({ left: 40, right: 40 })
      }
      .width('100%')
      
      Blank()
    }
    .layoutWeight(1)
    .width('100%')
  }
  
  // 已登录视图
  @Builder
  buildLoggedInView() {
    Scroll() {
      Column({ space: 24 }) {
        // 用户信息卡片
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.person_fill'))
            .fontSize(90)
            .fontColor(['#007DFF'])
          
          Text(this.userName)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)
          
          Text(`总点赞数: ${this.totalLikes}`)
            .fontSize(14)
            .fontColor(this.getColors().textTertiary)
          
          if (this.userRole === 'admin') {
            Text('管理员')
              .fontSize(12)
              .fontColor('#FF3B30')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('rgba(255, 59, 48, 0.15)')
              .borderRadius(6)
          }

          Text(this.loginStatusDebug)
            .fontSize(12)
            .fontColor(this.getColors().textTertiary)
            .textAlign(TextAlign.Center)
            .padding({ top: 4 })
        }
        .width('100%')
        .padding({ top: 20, bottom: 20 })
        .backgroundColor(this.getColors().cardBackground)
        .borderRadius(16)
        .shadow({ radius: 5, color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.05)', offsetY: 2 })
        
        // 统计卡片
        Row({ space: 16 }) {
          // 我的配方
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(32)
              .fontColor(['#007DFF'])
            
            Text('我的配方')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getColors().textPrimary)
            
            Text(`${this.myRecipesCount} 个`)
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
          }
          .layoutWeight(1)
          .padding(14)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(16)
          .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.04)', offsetY: 2 })
          .onClick(() => {
            router.pushUrl({
              url: '@bundle:com.example.cybar/entry/ets/pages/MyRecipesPage'
            }).catch((error: Error) => {
              console.error('[UserProfilePage] 跳转我的配方页面失败:', error);
              promptAction.showToast({ message: '跳转失败' });
            });
          })
          
          // 我的收藏
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(32)
              .fontColor(['#FFB800'])
            
            Text('我的收藏')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getColors().textPrimary)
            
            Text(`${this.favoritesCount} 个`)
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
          }
          .layoutWeight(1)
          .padding(14)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(16)
          .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.04)', offsetY: 2 })
          .onClick(() => {
            router.pushUrl({
              url: '@bundle:com.example.cybar/entry/ets/pages/MyFavoritesPage'
            }).catch((error: Error) => {
              console.error('[UserProfilePage] 跳转我的收藏页面失败:', error);
              promptAction.showToast({ message: '跳转失败' });
            });
          })
        }
        .width('100%')
        
        // 设置卡片
        Column({ space: 18 }) {
          // 管理员面板(仅管理员可见)
          if (this.userRole === 'admin') {
            Row() {
              SymbolGlyph($r('sys.symbol.gearshape_fill'))
                .fontSize(24)
                .fontColor([this.getColors().textSecondary])
                .margin({ right: 12 })
              
              Column({ space: 6 }) {
                Text('管理员面板')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getColors().textPrimary)
                  .alignSelf(ItemAlign.Start)
                
                Text('管理用户和配方')
                  .fontSize(12)
                  .fontColor(this.getColors().textTertiary)
                  .alignSelf(ItemAlign.Start)
              }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([this.getColors().textTertiary])
          }
          .width('100%')
          .padding(18)
          .onClick(() => {
            promptAction.showToast({ message: '功能开发中...' });
          })
          
          Divider()
            .color(this.getColors().divider)
        }          // 设置
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(24)
              .fontColor([this.getColors().textSecondary])
              .margin({ right: 12 })
            
            Column({ space: 6 }) {
              Text('设置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getColors().textPrimary)
                .alignSelf(ItemAlign.Start)
              
              Text('应用设置和偏好')
                .fontSize(12)
                .fontColor(this.getColors().textTertiary)
                .alignSelf(ItemAlign.Start)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([this.getColors().textTertiary])
          }
          .width('100%')
          .padding(18)
          .onClick(() => {
            router.pushUrl({
              url: '@bundle:com.example.cybar/entry/ets/pages/SettingsPage'
            }).catch((error: Error) => {
              console.error('[UserProfilePage] 跳转设置页面失败:', error);
              promptAction.showToast({ message: '跳转失败' });
            });
          })
          
          Divider()
            .color(this.getColors().divider)
          
          // 退出登录
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(24)
              .fontColor(['#FF3B30'])
              .margin({ right: 12 })
            
            Text('退出登录')
              .fontSize(16)
              .fontColor('#FF3B30')
              .fontWeight(FontWeight.Medium)
            
            Blank()
          }
          .width('100%')
          .padding(18)
          .onClick(() => {
            this.handleLogout();
          })
        }
        .width('100%')
        .backgroundColor(this.getColors().cardBackground)
        .borderRadius(16)
        .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.04)', offsetY: 2 })
      }
      .width('100%')
      .padding(16)
    }
    .layoutWeight(1)
    .width('100%')
  }
}
