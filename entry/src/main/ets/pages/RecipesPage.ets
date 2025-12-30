// RecipesPage.ets - 配方列表页面

import { apiService } from '../services/APIService';
import { Recipe, RecipesResponse, Ingredient } from '../models/Recipe';
import { router } from '@kit.ArkUI';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

// 分类配置接口
interface CategoryConfig {
  id: string;
  name: string;
  keywords: string[]; // 用于前端过滤的关键词
}

// 酒精度范围配置接口
interface AbvRange {
  id: string;
  name: string;
  min: number;
  max: number;
}

// 排序配置接口
interface SortOption {
  id: string;
  name: string;
}

interface InteractionUpdatePayload {
  id: string;
  likeCount: number;
  favoriteCount: number;
  isLiked: boolean;
  isFavorited: boolean;
  updatedAt?: number;
}

interface InteractionSnapshot {
  id: string;
  likeCount: number;
  favoriteCount: number;
  isLiked?: boolean;
  isFavorited?: boolean;
}

class BasicDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: Recipe[] = [];

  public totalCount(): number {
    return this.originDataArray.length;
  }

  public getData(index: number): Recipe {
    return this.originDataArray[index];
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
    })
  }

  public notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    })
  }

  public notifyDataChange(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChange(index);
    })
  }

  public notifyDataDelete(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDelete(index);
    })
  }

  public notifyDataMove(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMove(from, to);
    })
  }

  public setData(data: Recipe[]) {
    this.originDataArray = data;
    this.notifyDataReload();
  }

  public addData(data: Recipe[]) {
    const startIndex = this.originDataArray.length;
    this.originDataArray = this.originDataArray.concat(data);
    data.forEach((_, i) => {
        this.notifyDataAdd(startIndex + i);
    });
  }
}

@Entry
@Component
export struct RecipesPage {
  @State recipesDataSource: BasicDataSource = new BasicDataSource();
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State errorMessage: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('recipesRefreshTrigger') @Watch('onRefreshTrigger') refreshTrigger: number = 0;
  @StorageLink('lastRecipeInteraction') @Watch('onInteractionUpdate') interactionUpdate: InteractionUpdatePayload | null = null;
  
  // 筛选相关状态
  @State selectedCategory: string = 'all';     // 当前选中的基酒分类
  @State selectedAbvRange: string = 'all';     // 当前选中的酒精度范围
  @State showFilterPanel: boolean = false;     // 是否显示筛选面板
  @State allRecipes: Recipe[] = [];            // 存储所有配方(用于前端过滤)
  @State sortType: string = 'default';
  
  private pageSize: number = 10; 
  private categoryScroller: Scroller = new Scroller();
  
  // 分类配置
  private categories: CategoryConfig[] = [
    { id: 'all', name: '全部', keywords: [] },
    { id: 'vodka', name: '伏特加', keywords: ['伏特加', 'Vodka'] },
    { id: 'rum', name: '朗姆', keywords: ['朗姆', 'Rum'] },
    { id: 'tequila', name: '龙舌兰', keywords: ['龙舌兰', 'Tequila'] },
    { id: 'gin', name: '金酒', keywords: ['金酒', 'Gin'] },
  ];
  
  // 酒精度配置
  private abvRanges: AbvRange[] = [
    { id: 'all', name: '全部', min: 0, max: 100 },
    { id: 'low', name: '低度(0-20%)', min: 0, max: 20 },
    { id: 'medium', name: '中度(20-40%)', min: 20, max: 40 },
    { id: 'high', name: '高度(40%+)', min: 40, max: 100 }
  ];
  
  // 排序配置
  private sortOptions: SortOption[] = [
    { id: 'default', name: '最新' },
    { id: 'likes', name: '最热' },
    { id: 'favorites', name: '收藏' },
    { id: 'name', name: '名称' }
  ];
  
  // 获取当前主题色
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  // 刷新触发器回调
  onRefreshTrigger() {
    console.info('[RecipesPage] 检测到刷新触发器变化，刷新列表');
    this.refresh();
  }

  // 点赞/收藏本地同步
  onInteractionUpdate() {
    if (!this.interactionUpdate) {
      return;
    }
    this.applyInteractionUpdate(this.interactionUpdate as InteractionUpdatePayload);
  }

  aboutToAppear(): void {
    if (this.recipesDataSource.totalCount() === 0) {
      this.fetchRecipes(true);
    }
    // 回到列表时若有最近交互，立即同步本地显示
    if (this.interactionUpdate) {
      this.applyInteractionUpdate(this.interactionUpdate);
    }
  }

  // 页面重新可见时也强制同步一次并刷新，保持与用户中心同样的“返回即最新”体验
  onPageShow(): void {
    if (this.interactionUpdate) {
      this.applyInteractionUpdate(this.interactionUpdate);
    }
    if (!this.isLoading) {
      this.refresh();
    }
  }

  private async fetchRecipes(reset: boolean): Promise<void> {
    if (this.isLoading) return;
    
    if (reset) {
      this.currentPage = 1;
      this.totalPages = 1;
    }
    
    this.isLoading = true;
    this.errorMessage = '';
    
    try {
      const result: RecipesResponse = await apiService.fetchRecipes(
        this.currentPage,
        this.pageSize,
        '',
        this.sortType
      ) as RecipesResponse;
      
      const newRecipes: Array<Recipe> = result.recipes || [];
      console.info('[RecipesPage] 获取到的配方数量:', newRecipes.length);
      // 调试：输出服务器返回的每个配方的点赞/收藏数据
      const snapshot: InteractionSnapshot[] = newRecipes.map((r: Recipe): InteractionSnapshot => ({
        id: String(r.id),
        likeCount: r.likeCount,
        favoriteCount: r.favoriteCount,
        isLiked: r.isLiked,
        isFavorited: r.isFavorited
      }));
      console.info('[RecipesPage] 服务端交互数据快照 JSON:', JSON.stringify(snapshot));
      
      // 前端进行分类和酒精度过滤
      const filteredRecipes = this.filterRecipes(newRecipes);
      console.info('[RecipesPage] 过滤后的配方数量:', filteredRecipes.length);
      
      if (reset) {
        this.recipesDataSource.setData(filteredRecipes);
        this.allRecipes = newRecipes; // 保存原始数据
      } else {
        this.recipesDataSource.addData(filteredRecipes);
        this.allRecipes = this.allRecipes.concat(newRecipes);
      }

      // 拉取完成后同步最近一次交互，防止后端响应未带最新状态
      if (this.interactionUpdate) {
        this.applyInteractionUpdate(this.interactionUpdate);
      }
      
      this.currentPage = result.currentPage + 1;
      this.totalPages = result.totalPages;
      
    } catch (error) {
      console.error('[RecipesPage] Fetch failed:', error);
      this.errorMessage = '加载失败,请稍后重试';
    } finally {
      this.isLoading = false;
    }
  }

  private loadMore(): void {
    if (this.currentPage <= this.totalPages && !this.isLoading) {
      this.fetchRecipes(false);
    }
  }

  private refresh(): void {
    this.fetchRecipes(true);
  }

  /**
   * 处理下拉刷新事件
   * 这个方法在用户完成下拉动作时调用
   */
  private async handlePullRefresh(): Promise<void> {
    try {
      console.info('[RecipesPage] 开始下拉刷新');
      await this.fetchRecipes(true);
    } catch (error) {
      console.error('[RecipesPage] 下拉刷新失败:', error);
    } finally {
      // 下拉刷新完成后，设置 isRefreshing 为 false 以关闭刷新动画
      this.isRefreshing = false;
    }
  }
  
  // 前端过滤逻辑
  private filterRecipes(recipes: Recipe[]): Recipe[] {
    return recipes.filter(recipe => {
      // 1. 基酒分类过滤
      if (this.selectedCategory !== 'all') {
        const category = this.categories.find(c => c.id === this.selectedCategory);
        if (category) {
          const ingredients = typeof recipe.ingredients === 'string' 
            ? recipe.ingredients 
            : recipe.ingredients?.map(i => i.name).join(',') || '';
          
          const hasKeyword = category.keywords.some(keyword => 
            ingredients.toLowerCase().includes(keyword.toLowerCase())
          );
          
          if (!hasKeyword) return false;
        }
      }
      
      // 2. 酒精度过滤
      if (this.selectedAbvRange !== 'all') {
        const range = this.abvRanges.find(r => r.id === this.selectedAbvRange);
        if (range) {
          if (recipe.estimatedAbv < range.min || recipe.estimatedAbv > range.max) {
            return false;
          }
        }
      }
      
      return true;
    });
  }
  
  // 分类切换
  private onCategoryChange(categoryId: string, index: number): void {
    this.selectedCategory = categoryId;
    this.scrollToCategory(index);
    this.applyFilters();
  }
  
  // 滚动到指定分类
  private scrollToCategory(index: number): void {
    try {
      this.categoryScroller.scrollToIndex(index);
    } catch (e) {
      console.error('[RecipesPage] 滚动失败:', e);
    }
  }
  
  // 酒精度切换
  private onAbvRangeChange(rangeId: string): void {
    this.selectedAbvRange = rangeId;
    this.applyFilters();
  }
  
  // 排序切换
  private onSortChange(sortId: string): void {
    this.sortType = sortId;
    this.fetchRecipes(true);
  }
  
  // 应用筛选
  private applyFilters(): void {
    const filtered = this.filterRecipes(this.allRecipes);
    this.recipesDataSource.setData(filtered);
  }

  // 从存储的交互事件同步本地列表
  private applyInteractionUpdate(payload: InteractionUpdatePayload): void {
    try {
      const targetId = String(payload.id || '');
      if (!targetId || this.allRecipes.length === 0) return;

      const likeCount = this.parseNumberSafe(payload.likeCount);
      const favoriteCount = this.parseNumberSafe(payload.favoriteCount);
      const isLiked = payload.isLiked ? true : false;
      const isFavorited = payload.isFavorited ? true : false;

      const updatedAll: Recipe[] = [];
      for (let i = 0; i < this.allRecipes.length; i++) {
        const item: Recipe = this.allRecipes[i];
        const currentId = String(item.id || '');
        if (currentId === targetId) {
          if (likeCount >= 0) {
            item.likeCount = likeCount;
          }
          if (favoriteCount >= 0) {
            item.favoriteCount = favoriteCount;
          }
          item.isLiked = isLiked;
          item.isFavorited = isFavorited;
        }
        updatedAll.push(item);
      }

      this.allRecipes = updatedAll;
      this.applyFilters();
    } catch (e) {
      console.error('[RecipesPage] 本地交互同步失败:', e);
    }
  }

  private parseNumberSafe(value: string | number | null | undefined): number {
    if (value === null || value === undefined) {
      return -1;
    }
    if (typeof value === 'number') {
      return value;
    }
    const parsed: number = parseFloat(value);
    return parsed === parsed ? parsed : -1; // NaN 自身不等于自身
  }
  
  // 重置筛选
  private resetFilters(): void {
    this.selectedCategory = 'all';
    this.selectedAbvRange = 'all';
    this.sortType = 'default';
    this.showFilterPanel = false;
    this.fetchRecipes(true);
  }

  private openRecipeDetail(recipeId: string): void {
    router.pushUrl({
      url: 'pages/RecipeDetailPage',
      params: { recipeId: recipeId }
    });
  }

  @Builder footer(): void {
    Row() {
      if (this.isLoading) {
        LoadingProgress().width(20).height(20).margin({ right: 8 })
        Text('加载中...').fontSize(14).fontColor('#999999')
      } else if (this.currentPage > this.totalPages) {
        Text('没有更多了').fontSize(14).fontColor('#999999')
      }
    }
    .width('100%')
    .height(50)
    .justifyContent(FlexAlign.Center)
  }

  private goToSearch(): void {
    router.pushUrl({
      url: 'pages/SearchPage'
    });
  }
  
  // 分类栏组件
  @Builder CategoryBar() {
    Scroll(this.categoryScroller) {
      Row({ space: 16 }) {
        ForEach(this.categories, (category: CategoryConfig, index: number) => {
          Text(category.name)
            .fontSize(this.selectedCategory === category.id ? 16 : 14)
            .fontColor(this.selectedCategory === category.id 
              ? this.getColors().textPrimary
              : this.getColors().textTertiary)
            .fontWeight(this.selectedCategory === category.id 
              ? FontWeight.Bold 
              : FontWeight.Normal)
            .padding({ left: 8, right: 8, top: 8, bottom: 10 })
            .animation({
              duration: 200,
              curve: Curve.EaseInOut
            })
            .onClick(() => this.onCategoryChange(category.id, index))
        })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
  }
  
  // 筛选面板组件
  @Builder FilterPanel() {
    Column() {
      // 遮罩层
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showFilterPanel = false)
      
      // 筛选内容
      Column({ space: 16 }) {
        // 酒精度选择
        Column({ space: 8 }) {
          Text('酒精度')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
            .width('100%')
          
          Row({ space: 8 }) {
            ForEach(this.abvRanges, (range: AbvRange) => {
              Text(range.name)
                .fontSize(13)
                .fontColor(this.selectedAbvRange === range.id
                  ? '#FFFFFF'
                  : this.getColors().textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.selectedAbvRange === range.id
                  ? '#FF6B00'
                  : (this.isDarkMode ? '#2A2A2A' : '#F5F5F5'))
                .borderRadius(4)
                .onClick(() => this.onAbvRangeChange(range.id))
            })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        
        // 排序选择
        Column({ space: 8 }) {
          Text('排序')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
            .width('100%')
          
          Row({ space: 8 }) {
            ForEach(this.sortOptions, (option: SortOption) => {
              Text(option.name)
                .fontSize(13)
                .fontColor(this.sortType === option.id
                  ? '#FFFFFF'
                  : this.getColors().textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.sortType === option.id
                  ? '#FF6B00'
                  : (this.isDarkMode ? '#2A2A2A' : '#F5F5F5'))
                .borderRadius(4)
                .onClick(() => this.onSortChange(option.id))
            })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        
        // 按钮组
        Row({ space: 12 }) {
          Button('重置')
            .fontSize(14)
            .fontColor(this.getColors().textPrimary)
            .backgroundColor(this.isDarkMode ? '#2A2A2A' : '#F5F5F5')
            .layoutWeight(1)
            .onClick(() => this.resetFilters())
          
          Button('确定')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF6B00')
            .layoutWeight(1)
            .onClick(() => this.showFilterPanel = false)
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .padding(16)
      .backgroundColor(this.getColors().cardBackground)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        // Header
        Row() {
          Text('发现') 
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)
          
          Blank()
          
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(22)
            .fontColor([this.getColors().textPrimary])
            .margin({ right: 12 })
            .onClick(() => this.showFilterPanel = true)
          
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(22)
            .fontColor([this.getColors().textPrimary])
            .onClick(() => this.goToSearch())
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.getColors().cardBackground)

        // 分类栏
        this.CategoryBar()

        if (this.recipesDataSource.totalCount() === 0 && !this.isLoading) {
           Column() {
               Text('暂无内容').onClick(() => this.refresh())
           }.justifyContent(FlexAlign.Center).height('100%')
        } else {
          Refresh({ refreshing: $$this.isRefreshing, offset: 80, friction: 62 }) {
            WaterFlow({ footer: () => { this.footer() } }) {
              LazyForEach(this.recipesDataSource, (recipe: Recipe) => {
                FlowItem() {
                  RecipeCard({
                    recipe: recipe,
                    onTap: () => { this.openRecipeDetail(recipe.id) }
                  })
                }
                .width('100%')
              }, (recipe: Recipe) => recipe.id)
            }
            .columnsTemplate("1fr 1fr")
            .columnsGap(10)
            .rowsGap(10)
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .width('100%')
            .layoutWeight(1)
            .onReachEnd(() => {
                this.loadMore();
            })
          }
          .onStateChange((refreshStatus: RefreshStatus) => {
            console.info('[RecipesPage] 下拉刷新状态变化:', refreshStatus);
          })
          .onRefreshing(() => {
            console.info('[RecipesPage] 触发下拉刷新');
            this.handlePullRefresh();
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().background)
      
      // 筛选面板（悬浮）
      if (this.showFilterPanel) {
        this.FilterPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 配方卡片组件
 */
@Component
struct RecipeCard {
  @Prop recipe: Recipe;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State avatarLoadError: boolean = false;
  onTap?: () => void;
  
  // 默认图片和头像路径
  private readonly DEFAULT_WINE_IMAGE: string = '/uploads/cocktails/jiu.jpg';
  private readonly DEFAULT_AVATAR_PATH: string = '/uploads/avatars/test.jpg';
  
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  /**
   * 获取配方图片URL
   * 采用 RecipeDetailPage 的模式：本地图片不存在或为空则用默认图片
   */
  private getImageSource(): string | Resource {
    // 优先使用配方的图片，失败则用默认图片
    const imagePath = this.recipe.image || this.DEFAULT_WINE_IMAGE;
    return apiService.getFullImageUrl(imagePath);
  }

  /**
   * 获取作者头像URL
   * 优先使用后端返回的 creatorAvatar，失败则用默认头像
   */
  private getAvatarSource(): string | Resource {
    if (this.avatarLoadError) {
      return apiService.getFullImageUrl(this.DEFAULT_AVATAR_PATH);
    }
    
    // 优先使用后端返回的头像路径
    const avatarPath = Reflect.get(this.recipe, 'creatorAvatar') as string;
    if (avatarPath && avatarPath.length > 0) {
      return apiService.getFullImageUrl(avatarPath);
    }
    
    // 默认头像
    return apiService.getFullImageUrl(this.DEFAULT_AVATAR_PATH);
  }

  build() {
    Column() {
      // 配方图片区域
      Image(this.getImageSource())
        .width('100%')
        .height(180)
        .objectFit(ImageFit.Cover)
        .borderRadius({ topLeft: 8, topRight: 8 })
        .alt($r('app.media.wine'))
        .onComplete(() => {
          console.info(`[RecipeCard] 图片加载成功: ${this.recipe.name}`);
        })
        .onError(() => {
          console.error(`[RecipeCard] 图片加载失败: ${this.recipe.name}`);
          // 加载失败，Image 组件会使用 alt 的默认图片
        })
      
      // 内容区域
      Column() {
        // 标题
        Text(this.recipe.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.getColors().textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)
        
        // ABV + 配料标签
        Row({ space: 4 }) {
          Text(`${this.recipe.estimatedAbv.toFixed(0)}%`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF6B00')
            .backgroundColor(this.isDarkMode ? '#3D2A1A' : '#FFF0E0')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .flexShrink(0)
          
          if (this.recipe.ingredients && typeof this.recipe.ingredients === 'string') {
            Text(this.recipe.ingredients.split(',').slice(0, 5).join(' '))
              .fontSize(10)
              .fontColor(this.getColors().textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .margin({ top: 6 })
        .width('100%')
        
        // 👇 底部作者和互动数据 - 修改头像部分
        Row() {
          // 左边:头像+名字
          Row({ space: 8 }) {
            // 👇 替换为真实头像
            Image(this.getAvatarSource())
              .width(24)
              .height(24)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
              .flexShrink(0)
              .alt($r('app.media.profile_cat')) // 加载失败时显示默认图标
              .onError(() => {
                console.error(`[RecipeCard] 头像加载失败: ${this.recipe.createdBy}`);
                // 本地头像加载失败，标记为失败，下次调用 getAvatarSource 会返回默认头像
                if (!this.avatarLoadError) {
                  this.avatarLoadError = true;
                }
              })
            
            Text(this.recipe.createdBy)
              .fontSize(10)
              .fontColor(this.getColors().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          
          // 右边:点赞和收藏数量
          Row({ space: 8 }) {
            // 点赞
            Row({ space: 2 }) {
              SymbolGlyph(this.recipe.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(12)
                .fontColor([this.recipe.isLiked ? '#FF4D4F' : this.getColors().textSecondary])
              Text(`${this.recipe.likeCount}`)
                .fontSize(12)
                .fontColor(this.getColors().textSecondary)
            }

            // 收藏
            Row({ space: 2 }) {
              SymbolGlyph(this.recipe.isFavorited ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(12)
                .fontColor([this.recipe.isFavorited ? '#FFD700' : this.getColors().textSecondary])
              Text(`${this.recipe.favoriteCount}`)
                .fontSize(12)
                .fontColor(this.getColors().textSecondary)
            }
          }
          .flexShrink(0)
          .margin({ left: 4 })
        }
        .margin({ top: 8 })
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)

      }
      .padding(8)
      .backgroundColor(this.getColors().cardBackground)
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .borderRadius(8)
    .backgroundColor(this.getColors().cardBackground)
    .shadow({ radius: 4, color: this.isDarkMode ? '#00000000' : '#1A000000', offsetY: 2 })
    .onClick(() => {
      if (this.onTap) this.onTap();
    })
  }
}
