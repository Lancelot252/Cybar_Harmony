// UserProfilePage.ets - 用户中心页面 (小红书风格)
// 参照小红书主页风格重构

import APIService from '../services/APIService';
import { LoginPage } from './LoginPage';
import { RegisterPage } from './RegisterPage';
import { Recipe } from '../models/Recipe';
import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';
import picker from '@ohos.file.picker'; // 相册选择器
import fs from '@ohos.file.fs';         // 文件操作
import common from '@ohos.app.ability.common'; // 上下文类型

// Tab 类型枚举
enum ProfileTab {
  RECIPES = 0,    // 我的创作
  LIKES = 1,      // 我的点赞
  FAVORITES = 2   // 我的收藏
}

// 配方数据源类 - 用于 LazyForEach
class RecipeDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private dataArray: Recipe[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): Recipe {
    return this.dataArray[index];
  }

  public getAllData(): Recipe[] {
    return this.dataArray;
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  public notifyDataReload(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded();
    });
  }

  public setData(data: Recipe[]): void {
    this.dataArray = data;
    this.notifyDataReload();
  }

  public clear(): void {
    this.dataArray = [];
    this.notifyDataReload();
  }
}

@Component
export struct UserProfilePage {
  // 从外部传入的刷新触发器
  @Prop @Watch('onRefreshTriggerChange') refreshTrigger: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  @State isLoggedIn: boolean = false;
  @State userName: string = '未登录';
  @State userRole: string = '';
  @State userBio: string = '点击这里，填写简介';
  // ✅ [新增] 头像 URL 和默认路径常量
  @State avatarUrl: string = '';
  @State signature: string = '';
  private readonly DEFAULT_AVATAR_PATH = '/uploads/avatars/test.jpg';
  @State showLogin: boolean = false;
  @State showRegister: boolean = false;
  
  // 编辑资料相关状态
  @State showEditProfile: boolean = false;
  @State editNickname: string = '';
  @State editBio: string = '';
  @State isSavingProfile: boolean = false;
  
  // Tab 相关状态
  @State currentTab: ProfileTab = ProfileTab.RECIPES;
  
  // 数据源
  @State recipesDataSource: RecipeDataSource = new RecipeDataSource();
  @State likesDataSource: RecipeDataSource = new RecipeDataSource();
  @State favoritesDataSource: RecipeDataSource = new RecipeDataSource();
  
  // 数据状态
  @State favoritesCount: number = 0;
  @State myRecipesCount: number = 0;
  @State likesCount: number = 0;
  @State totalLikesReceived: number = 0; // 获赞与收藏
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State loadingFavorites: boolean = false;
  @State loadingMyRecipes: boolean = false;
  @State favoritesError: string = '';
  @State myRecipesError: string = '';
  @State loginStatusDebug: string = '';
  
  // 懒加载标志 - 标记数据是否已加载过
  private hasLoadedRecipes: boolean = false;
  private hasLoadedLikes: boolean = false;
  private hasLoadedFavorites: boolean = false;
  
  // 获取当前主题色
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }

  async handleAvatarClick() {
    try {
      // 1. 创建图库选择器
      const photoPicker = new picker.PhotoViewPicker();

      // 2. 打开选择界面
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });

      if (!result.photoUris || result.photoUris.length === 0) {
        return; // 用户取消了选择
      }

      const selectedUri = result.photoUris[0];
      console.info('[UserProfilePage] 用户选择了图片:', selectedUri);

      // 3. 将图片从图库拷贝到应用沙箱 Cache 目录 (上传任务必须读取沙箱文件)
      const context = getContext(this) as common.UIAbilityContext;
      const fileName = `avatar_${Date.now()}.jpg`; // 生成唯一文件名
      const cacheDir = context.cacheDir;
      const targetPath = `${cacheDir}/${fileName}`;

      // 打开源文件 (只读)
      const file = fs.openSync(selectedUri, fs.OpenMode.READ_ONLY);
      // 拷贝到目标路径
      fs.copyFileSync(file.fd, targetPath);
      fs.closeSync(file);

      console.info('[UserProfilePage] 图片已拷贝到沙箱:', targetPath);

      // 4. 显示加载提示
      promptAction.showToast({ message: '正在上传头像...' });

      // 5. 调用 APIService 上传
      await APIService.getInstance().uploadAvatar(context, targetPath);

      // 6. 成功提示 (uploadAvatar 内部成功后会自动 fetchCurrentUser，所以界面会自动更新)
      promptAction.showToast({ message: '头像修改成功' });

      // 清理缓存文件 (可选)
      try { fs.unlinkSync(targetPath); } catch(e) {}

    } catch (error) {
      console.error('[UserProfilePage] 修改头像流程失败:', error);
      promptAction.showToast({ message: '上传失败，请重试' });
    }
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

      // ✅ [新增] 获取签名，如果没有则显示默认文案
      this.signature = apiService.currentUser.signature || '这个人很懒，什么都没写';
      // ✅ [修复] 同步 userBio 和 signature
      this.userBio = this.signature;
      // ✅ [新增] 核心逻辑：读取头像并转换为完整链接
      // 如果 currentUser.avatar 为空，就使用默认路径
      const rawPath = apiService.currentUser.avatar || this.DEFAULT_AVATAR_PATH;
      this.avatarUrl = apiService.getFullImageUrl(rawPath);
    } else {
      this.userName = '未登录';
      this.userRole = '';
      this.userBio = '点击这里，填写简介';
      // ✅ [新增] 未登录时重置头像
      this.avatarUrl = '';
      this.signature = '';
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
  private async refreshAll(force: boolean = false) {
    try {
      // 1. 先去服务器拉取最新头像和用户信息
      await APIService.getInstance().fetchCurrentUser();
    } catch (error) {
      console.error('刷新用户信息失败:', error);
    }

    if (force) {
      // 强制刷新时重置标志
      this.hasLoadedRecipes = false;
      this.hasLoadedLikes = false;
      this.hasLoadedFavorites = false;
      this.totalLikesReceived = 0;
    }
    
    // 只加载未加载过的数据
    if (!this.hasLoadedRecipes) {
      this.loadMyRecipes();
    }
    if (!this.hasLoadedFavorites) {
      this.loadFavorites();
    }
    if (!this.hasLoadedLikes) {
      this.loadLikes();
    }
  }
  
  // 刷新当前 Tab 数据
  private async refreshCurrentTab(force: boolean = false): Promise<void> {
    switch (this.currentTab) {
      case ProfileTab.RECIPES:
        if (force) this.hasLoadedRecipes = false;
        await this.loadMyRecipes();
        break;
      case ProfileTab.LIKES:
        if (force) this.hasLoadedLikes = false;
        await this.loadLikes();
        break;
      case ProfileTab.FAVORITES:
        if (force) this.hasLoadedFavorites = false;
        await this.loadFavorites();
        break;
    }
  }
  
  // 清空数据
  private clearData() {
    // 重置懒加载标志
    this.hasLoadedRecipes = false;
    this.hasLoadedLikes = false;
    this.hasLoadedFavorites = false;
    
    this.favoritesCount = 0;
    this.myRecipesCount = 0;
    this.likesCount = 0;
    this.totalLikesReceived = 0;
    this.favoritesError = '';
    this.myRecipesError = '';
    this.recipesDataSource.clear();
    this.likesDataSource.clear();
    this.favoritesDataSource.clear();
  }
  
  // 解析数字
  private parseNumber(value: ESObject): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }
  
  // 解析配方数据
  private parseRecipe(item: ESObject): Recipe {
    return {
      id: (item['id'] || '') as string,
      name: (item['name'] || '未命名') as string,
      createdBy: (item['createdBy'] || item['created_by'] || '未知') as string,
      instructions: (item['instructions'] || '') as string,
      estimatedAbv: this.parseNumber(item['estimatedAbv'] || item['estimated_abv']),
      likeCount: this.parseNumber(item['likeCount'] || item['like_count']),
      favoriteCount: this.parseNumber(item['favoriteCount'] || item['favorite_count']),
      ingredients: (item['ingredients'] || '') as string,
      image: (item['image'] || '') as string  // 解析图片路径
    };
  }
  
  // 加载收藏列表
  private async loadFavorites(): Promise<void> {
    this.loadingFavorites = true;
    this.favoritesError = '';
    
    try {
      const apiService = APIService.getInstance();
      const favorites = await apiService.fetchUserFavorites();
      if (Array.isArray(favorites) && favorites.length > 0) {
        this.favoritesCount = favorites.length;
        
        // 获取每个配方的详细信息
        const detailedRecipes: Recipe[] = [];
        for (const item of favorites) {
          try {
            const recipeId = (item['id'] || '') as string;
            if (recipeId) {
              const detail = await apiService.fetchRecipeDetail(recipeId);
              detailedRecipes.push(this.parseRecipe(detail as ESObject));
            }
          } catch (e) {
            // 如果获取详情失败，使用预览数据
            detailedRecipes.push(this.parseRecipe(item as ESObject));
          }
        }
        this.favoritesDataSource.setData(detailedRecipes);
      } else {
        this.favoritesCount = 0;
        this.favoritesDataSource.clear();
      }
    } catch (error) {
      this.favoritesError = error instanceof Error ? error.message : '加载失败';
      this.favoritesDataSource.clear();
    } finally {
      this.loadingFavorites = false;
      this.hasLoadedFavorites = true;
    }
  }
  
  // 加载点赞列表
  private async loadLikes(): Promise<void> {
    this.isLoading = true;
    
    try {
      const apiService = APIService.getInstance();
      const likes = await apiService.fetchUserLikes();
      if (Array.isArray(likes) && likes.length > 0) {
        this.likesCount = likes.length;
        
        // 获取每个配方的详细信息
        const detailedRecipes: Recipe[] = [];
        for (const item of likes) {
          try {
            const recipeId = (item['id'] || '') as string;
            if (recipeId) {
              const detail = await apiService.fetchRecipeDetail(recipeId);
              detailedRecipes.push(this.parseRecipe(detail as ESObject));
            }
          } catch (e) {
            // 如果获取详情失败，使用预览数据
            detailedRecipes.push(this.parseRecipe(item as ESObject));
          }
        }
        this.likesDataSource.setData(detailedRecipes);
      } else {
        this.likesCount = 0;
        this.likesDataSource.clear();
      }
    } catch (error) {
      console.error('[UserProfilePage] 加载点赞列表失败:', error);
      this.likesDataSource.clear();
    } finally {
      this.isLoading = false;
      this.hasLoadedLikes = true;
    }
  }
  
  // 加载我的配方
  private async loadMyRecipes(): Promise<void> {
    this.loadingMyRecipes = true;
    this.myRecipesError = '';
    
    try {
      const apiService = APIService.getInstance();
      const recipes = await apiService.fetchUserCreatedRecipes();
      
      if (Array.isArray(recipes) && recipes.length > 0) {
        this.myRecipesCount = recipes.length;
        
        // 获取每个配方的详细信息并计算总获赞与收藏
        const detailedRecipes: Recipe[] = [];
        let totalLikes = 0;
        let totalFavorites = 0;
        
        for (const item of recipes) {
          try {
            const recipeId = (item['id'] || '') as string;
            if (recipeId) {
              const detail = await apiService.fetchRecipeDetail(recipeId);
              const parsedRecipe = this.parseRecipe(detail as ESObject);
              detailedRecipes.push(parsedRecipe);
              totalLikes += parsedRecipe.likeCount;
              totalFavorites += parsedRecipe.favoriteCount;
            }
          } catch (e) {
            // 如果获取详情失败，使用预览数据
            const parsedRecipe = this.parseRecipe(item as ESObject);
            detailedRecipes.push(parsedRecipe);
            totalLikes += parsedRecipe.likeCount;
            totalFavorites += parsedRecipe.favoriteCount;
          }
        }
        
        this.recipesDataSource.setData(detailedRecipes);
        this.totalLikesReceived = totalLikes + totalFavorites;
      } else {
        this.myRecipesCount = 0;
        this.totalLikesReceived = 0;
        this.recipesDataSource.clear();
      }
    } catch (error) {
      this.myRecipesError = error instanceof Error ? error.message : '加载失败';
      this.totalLikesReceived = 0;
      this.recipesDataSource.clear();
    } finally {
      this.loadingMyRecipes = false;
      this.hasLoadedRecipes = true;
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
  
  // 每次页面显示时检查登录状态（不再自动刷新数据）
  onPageShow() {
    console.info('[UserProfilePage] onPageShow triggered');
    // 只更新登录状态，不重新加载数据（懒加载）
    this.updateFromAPIService();
  }
  
  build() {
    Stack() {
      Column() {
        if (this.isLoggedIn) {
          // 已登录状态 - 小红书风格
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
      
      // 编辑资料弹窗
      if (this.showEditProfile) {
        this.buildEditProfileSheet()
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
      
        Row({ space: 12 }) {
          Stack() {
            // 使用真实头像，加载失败回退默认头像
            Image(this.avatarUrl || APIService.getInstance().getFullImageUrl(this.DEFAULT_AVATAR_PATH))
              .width(70)
              .height(70)
              .borderRadius(35)
              .objectFit(ImageFit.Cover)
              .backgroundColor(this.getColors().divider)
              .border({ width: 1, color: this.getColors().divider })
              .onError(() => {
                const fallback = APIService.getInstance().getFullImageUrl(this.DEFAULT_AVATAR_PATH);
                if (this.avatarUrl !== fallback) {
                  this.avatarUrl = fallback;
                }
              })

            if (this.userRole === 'admin') {
              // 管理员徽章
              Text('V')
                .fontSize(10)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
                .width(18)
                .height(18)
                .textAlign(TextAlign.Center)
                .backgroundColor('#FF3B30')
                .borderRadius(9)
                .position({ x: 52, y: 52 })
            }
          }
          .width(70)
          .height(70)
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
  
  // 已登录视图 - 小红书风格
  @Builder
  buildLoggedInView() {
    Stack() {
      // 顶部背景图片
      Image($r('app.media.profile_default_background'))
        .width('100%')
        .height(200)
        .objectFit(ImageFit.Cover)
        .position({ x: 0, y: 0 })
      
      // 背景渐变遮罩
      Column()
        .width('100%')
        .height(200)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            ['rgba(0, 0, 0, 0)', 0],
            [this.getColors().background as string, 1]
          ]
        })
        .position({ x: 0, y: 0 })
      
      // 主体内容
      Column() {
        // 顶部工具栏
        Row() {
          Blank()
          
          Row({ space: 16 }) {
            // 设置按钮
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(24)
              .fontColor([Color.White])
              .onClick(() => {
                router.pushUrl({
                  url: '@bundle:com.example.cybar/entry/ets/pages/SettingsPage'
                }).catch((error: Error) => {
                  console.error('[UserProfilePage] 跳转设置页面失败:', error);
                });
              })
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        
        // 主体内容 - 下拉刷新
        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll() {
            Column() {
              // 用户信息区域
              this.buildUserInfoSection()
              
              // Tab 切换栏
              this.buildTabBar()
              
              // 内容列表
              this.buildContentList()
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
        .onRefreshing(async () => {
          // 下拉刷新时强制重新加载当前 Tab 数据
          await this.refreshCurrentTab(true);
          this.isRefreshing = false;
        })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
  
  // 用户信息区域
  @Builder
  buildUserInfoSection() {
    Column({ space: 12 }) {
      Row({ space: 16 }) {
        // 头像（真实头像 + 失败回退默认）
        Stack() {
          Image(this.avatarUrl || APIService.getInstance().getFullImageUrl(this.DEFAULT_AVATAR_PATH))
            .width(70)
            .height(70)
            .borderRadius(35)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.getColors().divider)
            .border({ width: 1, color: this.getColors().divider })
            .alt(APIService.getInstance().getFullImageUrl(this.DEFAULT_AVATAR_PATH))
            .onError(() => {
              // 头像加载失败，自动使用 .alt() 设置的默认头像
            })
          
          if (this.userRole === 'admin') {
            // 管理员徽章
            Text('V')
              .fontSize(10)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .width(18)
              .height(18)
              .textAlign(TextAlign.Center)
              .backgroundColor('#FF3B30')
              .borderRadius(9)
              .position({ x: 52, y: 52 })
          }
        }
        .width(70)
        .height(70)
        
        // 用户名和简介
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(this.userName)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().textPrimary)
            
            if (this.userRole === 'admin') {
              Text('管理员')
                .fontSize(10)
                .fontColor('#FF3B30')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('rgba(255, 59, 48, 0.15)')
                .borderRadius(4)
            }
          }
          .alignItems(VerticalAlign.Center)
          
          Text(this.userBio)
            .fontSize(13)
            .fontColor(this.getColors().textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      
      // 统计数据行
      Row() {
        // 获赞与收藏
        Column({ space: 4 }) {
          Text(`${this.totalLikesReceived}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)
          
          Text('获赞与收藏')
            .fontSize(12)
            .fontColor(this.getColors().textSecondary)
        }
        .layoutWeight(1)
        
        // 分隔线
        Divider()
          .vertical(true)
          .height(30)
          .color(this.getColors().divider)
        
        // 编辑资料按钮
        Button('编辑资料')
          .fontSize(13)
          .fontColor(this.getColors().textPrimary)
          .backgroundColor(this.getColors().secondaryBackground)
          .borderRadius(16)
          .height(32)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.editNickname = this.userName;
            // ✅ [修复] 直接使用 signature，如果是默认文案则清空
            this.editBio = this.signature === '这个人很懒，什么都没写' ? '' : this.signature;
            this.showEditProfile = true;
          })
        
        // 设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(16)
            .fontColor([this.getColors().textPrimary])
        }
        .width(32)
        .height(32)
        .backgroundColor(this.getColors().secondaryBackground)
        .borderRadius(16)
        .margin({ left: 8 })
        .onClick(() => {
          router.pushUrl({
            url: '@bundle:com.example.cybar/entry/ets/pages/SettingsPage'
          }).catch((error: Error) => {
            console.error('[UserProfilePage] 跳转设置页面失败:', error);
          });
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
  }
  
  // Tab 切换栏
  @Builder
  buildTabBar() {
    Column() {
      Row() {
        // 笔记 (我的创作)
        this.buildTabItem('笔记', ProfileTab.RECIPES, this.myRecipesCount)
        
        // 点赞
        this.buildTabItem('点赞', ProfileTab.LIKES, this.likesCount)
        
        // 收藏
        this.buildTabItem('收藏', ProfileTab.FAVORITES, this.favoritesCount)
        
        Blank()
        
        // 搜索按钮
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([this.getColors().textSecondary])
          .margin({ right: 16 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16 })
      
      // 底部分隔线
      Divider()
        .color(this.getColors().divider)
    }
    .width('100%')
    .backgroundColor(this.getColors().cardBackground)
  }
  
  // Tab 项
  @Builder
  buildTabItem(title: string, tab: ProfileTab, count: number) {
    Column() {
      Row({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === tab ? this.getColors().textPrimary : this.getColors().textSecondary)
        
        if (count > 0) {
          Text(`${count}`)
            .fontSize(12)
            .fontColor(this.getColors().textTertiary)
        }
      }
      
      // 下划线指示器
      if (this.currentTab === tab) {
        Divider()
          .width(24)
          .strokeWidth(2)
          .color('#007DFF')
          .margin({ top: 8 })
      }
    }
    .height('100%')
    .padding({ right: 24 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.currentTab !== tab) {
        this.currentTab = tab;
        this.refreshCurrentTab();
      }
    })
  }
  
  // 内容列表
  @Builder
  buildContentList() {
    Column() {
      if (this.isLoading || this.loadingMyRecipes || this.loadingFavorites) {
        // 加载中
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.getColors().primary)
          
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        // 根据当前 Tab 显示对应列表
        if (this.currentTab === ProfileTab.RECIPES) {
          this.buildRecipeGrid(this.recipesDataSource, '还没有创作配方', '去创作你的第一个配方吧')
        } else if (this.currentTab === ProfileTab.LIKES) {
          this.buildRecipeGrid(this.likesDataSource, '还没有点赞', '去发现喜欢的配方吧')
        } else {
          this.buildRecipeGrid(this.favoritesDataSource, '还没有收藏', '去收藏喜欢的配方吧')
        }
      }
    }
    .width('100%')
    .backgroundColor(this.getColors().background)
  }
  
  // 配方网格
  @Builder
  buildRecipeGrid(dataSource: RecipeDataSource, emptyTitle: string, emptySubtitle: string) {
    if (dataSource.totalCount() === 0) {
      // 空状态
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(60)
          .fontColor([this.getColors().textTertiary])
        
        Text(emptyTitle)
          .fontSize(16)
          .fontColor(this.getColors().textSecondary)
        
        Text(emptySubtitle)
          .fontSize(13)
          .fontColor(this.getColors().textTertiary)
      }
      .width('100%')
      .height(250)
      .justifyContent(FlexAlign.Center)
    } else {
      // 使用 Grid 布局替代 WaterFlow，避免嵌套滚动问题
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(dataSource.getAllData(), (recipe: Recipe) => {
          Column() {
            this.buildRecipeCard(recipe)
          }
          .width('48%')
          .margin({ bottom: 12 })
        }, (recipe: Recipe) => recipe.id)
      }
      .padding({ left: 12, right: 12, top: 12, bottom: 80 })
      .width('100%')
    }
  }
  
  // 获取配方图片源
  private getRecipeImageSource(recipe: Recipe): string | Resource {
    if (recipe.image && recipe.image.length > 0 && recipe.image.startsWith('/')) {
      return APIService.getInstance().baseUrl + recipe.image;
    }
    return $r('app.media.wine');
  }

  // 配方卡片
  @Builder
  buildRecipeCard(recipe: Recipe) {
    Column() {
      // 配方图片
      Stack() {
        Image(recipe.image && recipe.image.length > 0 ? 
          APIService.getInstance().getFullImageUrl(recipe.image) : 
          $r('app.media.wine'))
          .width('100%')
          .height(140)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .alt($r('app.media.wine'))
          .onError(() => {
            // 图片加载失败，自动使用 .alt() 设置的默认图片
          })
        
        // ABV 标签
        if (recipe.estimatedAbv > 0) {
          Text(`${recipe.estimatedAbv.toFixed(1)}%`)
            .fontSize(10)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .borderRadius(4)
            .position({ x: 8, y: 8 })
        }
      }
      .width('100%')
      
      // 配方信息
      Column({ space: 4 }) {
        Text(recipe.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(12)
              .fontColor(['#ffff0000'])
            
            Text(`${recipe.likeCount}`)
              .fontSize(11)
              .fontColor(this.getColors().textTertiary)
          }
          
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(12)
              .fontColor(['#FFB800'])
            
            Text(`${recipe.favoriteCount}`)
              .fontSize(11)
              .fontColor(this.getColors().textTertiary)
          }
        }

        // 我的创作下显示“编辑”入口
        if (this.currentTab === ProfileTab.RECIPES) {
          Row() {
            Blank()
            Button('编辑')
              .type(ButtonType.Capsule)
              .height(26)
              .fontSize(12)
              .backgroundColor(this.getColors().secondaryBackground)
              .fontColor(this.getColors().textPrimary)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/EditRecipePage',
                  params: { recipeId: recipe.id }
                }).catch((error: Error) => {
                  console.error('[UserProfilePage] 跳转编辑页面失败:', error);
                });
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(8)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(this.getColors().cardBackground)
    .borderRadius(8)
    .shadow({ radius: 2, color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.05)', offsetY: 1 })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/RecipeDetailPage',
        params: { recipeId: recipe.id }
      }).catch((error: Error) => {
        console.error('[UserProfilePage] 跳转配方详情失败:', error);
      });
    })
  }
  
  // 编辑资料弹窗
  @Builder
  buildEditProfileSheet() {
    Column() {
      // 半透明背景遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {
          if (!this.isSavingProfile) {
            this.showEditProfile = false;
          }
        })
      
      // 底部弹出面板
      Column() {
        // 顶部拖动条
        Row() {
          Column()
            .width(40)
            .height(4)
            .backgroundColor(this.getColors().divider)
            .borderRadius(2)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 16 })
        
        // 标题栏
        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(this.getColors().textSecondary)
            .onClick(() => {
              if (!this.isSavingProfile) {
                this.showEditProfile = false;
              }
            })
          
          Blank()
          
          Text('编辑资料')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)
          
          Blank()
          
          if (this.isSavingProfile) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#007DFF')
          } else {
            Text('保存')
              .fontSize(16)
              .fontColor('#007DFF')
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                this.saveProfile();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
        
        // 头像区域
        Column({ space: 8 }) {
          Stack() {
            // ✅ [核心修改] 将原来的 SymbolGlyph 替换为 Image 组件
            Image(this.avatarUrl)
              .width(80)
              .height(80)
              .borderRadius(40)
              .objectFit(ImageFit.Cover)
              .backgroundColor(this.getColors().divider)
              .border({ width: 1, color: this.getColors().divider })
              .alt(APIService.getInstance().getFullImageUrl(this.DEFAULT_AVATAR_PATH))
              .onError(() => {
                // 头像加载失败，自动使用 .alt() 设置的默认头像
              })
            
            // 编辑图标
            Column() {
              SymbolGlyph($r('sys.symbol.camera_fill'))
                .fontSize(14)
                .fontColor([Color.White])
            }
            .width(28)
            .height(28)
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .borderRadius(14)
            .justifyContent(FlexAlign.Center)
            .position({ x: 52, y: 52 })
          }
          .width(80)
          .height(80)
          
          Text('点击更换头像')
            .fontSize(13)
            .fontColor(this.getColors().textTertiary)
        }
        .width('100%')
        .padding({ bottom: 24 })
        .onClick(() => {
          // ✅ [核心修改] 调用真实的上传头像功能
          this.handleAvatarClick();
        })
        
        // 表单区域
        Column({ space: 0 }) {
          // 昵称输入
          Row() {
            Text('昵称')
              .fontSize(15)
              .fontColor(this.getColors().textPrimary)
              .width(70)
            
            TextInput({ text: this.editNickname, placeholder: '请输入昵称' })
              .fontSize(15)
              .fontColor(this.getColors().textPrimary)
              .placeholderColor(this.getColors().textTertiary)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.editNickname = value;
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          
          Divider()
            .color(this.getColors().divider)
            .margin({ left: 16 })
          
          // 简介输入
          Row() {
            Text('简介')
              .fontSize(15)
              .fontColor(this.getColors().textPrimary)
              .width(70)
            
            TextInput({ text: this.editBio, placeholder: '介绍一下自己吧' })
              .fontSize(15)
              .fontColor(this.getColors().textPrimary)
              .placeholderColor(this.getColors().textTertiary)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.editBio = value;
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .backgroundColor(this.getColors().cardBackground)
        .borderRadius(12)
        .margin({ left: 16, right: 16 })
        
        // 提示文字
        Text('昵称和简介将展示在你的个人主页')
          .fontSize(12)
          .fontColor(this.getColors().textTertiary)
          .margin({ top: 12, left: 16 })
          .width('100%')
        
        Blank()
      }
      .width('100%')
      .height('70%')
      .backgroundColor(this.getColors().background)
      .borderRadius({ topLeft: 16, topRight: 16 })
      .position({ y: '30%' })
    }
    .width('100%')
    .height('100%')
    .transition({ type: TransitionType.Insert, opacity: 0 })
    .transition({ type: TransitionType.Delete, opacity: 0 })
  }
  
  // 保存用户资料
  private async saveProfile(): Promise<void> {
    if (this.isSavingProfile) {
      return;
    }
    
    // 验证输入
    if (this.editNickname.trim().length === 0) {
      promptAction.showToast({ message: '昵称不能为空' });
      return;
    }
    
    if (this.editNickname.trim().length > 20) {
      promptAction.showToast({ message: '昵称不能超过20个字符' });
      return;
    }
    
    if (this.editBio.length > 50) {
      promptAction.showToast({ message: '简介不能超过50个字符' });
      return;
    }
    
    this.isSavingProfile = true;
    
    try {
      const apiService = APIService.getInstance();
      // 调用 API 更新用户资料
      await apiService.updateUserProfile(this.editNickname.trim(), this.editBio.trim());
      
      // ✅ 保存成功后，重新从服务器获取最新数据
      await apiService.fetchCurrentUser();
      
      // 本地状态会通过 stateChangeListener 自动更新
      promptAction.showToast({ message: '保存成功' });
      this.showEditProfile = false;
    } catch (error) {
      console.error('[UserProfilePage] 保存资料失败:', error);
      const errorMessage = error instanceof Error ? error.message : '保存失败，请重试';
      promptAction.showToast({ message: errorMessage });
    } finally {
      this.isSavingProfile = false;
    }
  }
  
  // 退出登录菜单（在设置中处理）
}
