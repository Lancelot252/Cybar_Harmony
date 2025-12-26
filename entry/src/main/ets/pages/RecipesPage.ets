// RecipesPage.ets - 配方列表页面

import APIService, { apiService } from '../services/APIService';
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

@Component
export struct RecipesPage {
  @State recipesDataSource: BasicDataSource = new BasicDataSource();
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State errorMessage: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
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

  aboutToAppear(): void {
    if (this.recipesDataSource.totalCount() === 0) {
      this.fetchRecipes(true);
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
      const result: object = await apiService.fetchRecipes(
        this.currentPage,
        this.pageSize,
        '',
        this.sortType
      );
      
      const response: RecipesResponse = result as RecipesResponse;
      const newRecipes: Array<Recipe> = response.recipes || [];
      console.info('[RecipesPage] 获取到的配方数量:', newRecipes.length);
      
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
      
      this.currentPage = response.currentPage + 1;
      this.totalPages = response.totalPages;
      
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
    setTimeout(() => {
    this.fetchRecipes(true);
  }, 50);
  }
  
  // 应用筛选
  private applyFilters(): void {
    const filtered = this.filterRecipes(this.allRecipes);
    this.recipesDataSource.setData(filtered);
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
  @State imageLoadError: boolean = false;
  @State avatarLoadError: boolean = false; // 👈 新增:头像加载失败状态
  onTap?: () => void;
  
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  private getImageSource(): string | Resource {
    if (this.imageLoadError || !this.recipe.image) {
      return $r('app.media.wine');
    }
    
    if (this.recipe.image.startsWith('/')) {
      const fullUrl = APIService.getInstance().baseUrl + this.recipe.image;
      return fullUrl;
    }
    
    return this.recipe.image;
  }

  // 👇 新增:获取作者头像URL
  private getAvatarSource(): string | Resource {
    if (this.avatarLoadError || !this.recipe.creatorAvatar) {
      console.info('头像加载失败,[RecipeCard] 使用默认头像');
      return $r('app.media.profile_cat'); // 默认头像
    }
    
    if (this.recipe.creatorAvatar.startsWith('/')) {
      const fullUrl = 'http://47.101.11.98:8080' + this.recipe.creatorAvatar;
      return fullUrl;
    }
    
    return this.recipe.creatorAvatar;
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
          this.imageLoadError = true;
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
                this.avatarLoadError = true;
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
