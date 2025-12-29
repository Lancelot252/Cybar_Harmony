// RecommendationsPage.ets - 推荐页面 (沉浸式双列瀑布流)
// 包含「推荐」和「热榜」两个Tab
// 参考 RecipesPage 的瀑布流实现

import { router } from '@kit.ArkUI';
import APIService from '../services/APIService';
import { Recipe, RecipesResponse, Ingredient, RecommendedRecipe, RecommendationsResponse } from '../models/Recipe';
import promptAction from '@ohos.promptAction';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

// Tab类型枚举
enum TabType {
  RECOMMENDATION = 0,
  HOT = 1
}

// 推荐配方数据源类 - 用于LazyForEach
class RecommendedRecipeDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: RecommendedRecipe[] = [];

  public totalCount(): number {
    return this.originDataArray.length;
  }

  public getData(index: number): RecommendedRecipe {
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

  public setData(data: RecommendedRecipe[]) {
    this.originDataArray = data;
    this.notifyDataReload();
  }

  public addData(data: RecommendedRecipe[]) {
    const startIndex = this.originDataArray.length;
    this.originDataArray = this.originDataArray.concat(data);
    data.forEach((_, i) => {
      this.notifyDataAdd(startIndex + i);
    });
  }

  public notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    })
  }

  public clear() {
    this.originDataArray = [];
    this.notifyDataReload();
  }
}

// 热榜配方数据源类 - 用于LazyForEach
class RecipeDataSource implements IDataSource {
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

  public clear() {
    this.originDataArray = [];
    this.notifyDataReload();
  }
}

@Component
export struct RecommendationsPage {
  // Tab状态
  @State currentTab: TabType = TabType.RECOMMENDATION;
  @State selectedTabIndex: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  // 推荐Tab数据
  @State recommendDataSource: RecommendedRecipeDataSource = new RecommendedRecipeDataSource();
  @State isLoadingRecommend: boolean = false;
  @State isRefreshingRecommend: boolean = false;
  @State recommendPage: number = 1;
  @State recommendTotalPages: number = 1;
  @State recommendError: string = '';
  @State recommendMessage: string = ''; // 无推荐时的提示信息
  @State recommendDataVersion: number = 0; // 数据版本号，用于强制刷新
  @State showMatchPercentage: boolean = true; // 是否显示匹配度标签
  @State showRecommendReason: boolean = true; // 是否显示推荐理由
  
  // 热榜Tab数据
  @State hotDataSource: RecipeDataSource = new RecipeDataSource();
  @State isLoadingHot: boolean = false;
  @State isRefreshingHot: boolean = false;
  @State hotPage: number = 1;
  @State hotTotalPages: number = 1;
  @State hotError: string = '';
  @State hotDataVersion: number = 0; // 数据版本号，用于强制刷新
  
  private pageSize: number = 20; // 每页加载数量
  private scroller: Scroller = new Scroller();
  
  // 获取当前主题色
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  aboutToAppear(): void {
    // 初始加载推荐Tab数据
    if (this.recommendDataSource.totalCount() === 0) {
      this.loadRecommendations(true);
    }
  }
  
  /**
   * 加载推荐Tab数据 (使用后端推荐算法，支持分页)
   */
  private async loadRecommendations(reset: boolean): Promise<void> {
    if (this.isLoadingRecommend) return;
    
    if (reset) {
      this.recommendPage = 1;
      this.recommendTotalPages = 1;
    }
    
    this.isLoadingRecommend = true;
    this.recommendError = '';
    this.recommendMessage = '';
    
    try {
      const apiService = APIService.getInstance();
      const response: RecommendationsResponse = await apiService.fetchRecommendations(this.recommendPage, 10);
      
      console.info(`[RecommendationsPage] API响应:`, JSON.stringify(response));
      
      const recommendations: Array<RecommendedRecipe> = response.recommendations || [];
      
      if (recommendations.length === 0 && response.message) {
        this.recommendMessage = response.message;
      }
      
      // 打印每个推荐的详细信息
      recommendations.forEach((rec, index) => {
        console.info(`[RecommendationsPage] 推荐${index}: id=${rec.id}, name=${rec.name}, abv=${rec.estimatedAbv}, match=${rec.matchPercentage}%`);
      });
      
      if (reset) {
        this.recommendDataSource.setData(recommendations);
        // 刷新时更新版本号，强制LazyForEach重新渲染
        this.recommendDataVersion++;
      } else {
        this.recommendDataSource.addData(recommendations);
      }
      
      // 更新分页信息
      if (response.pagination) {
        this.recommendPage = response.pagination.currentPage + 1;
        this.recommendTotalPages = response.pagination.totalPages;
      }
      
      console.info(`[RecommendationsPage] 推荐加载成功: ${recommendations.length}条, 第${response.pagination?.currentPage}页/${response.pagination?.totalPages}页`);
    } catch (error) {
      console.error('[RecommendationsPage] 推荐加载失败:', error);
      this.recommendError = '加载失败，请稍后重试';
    } finally {
      this.isLoadingRecommend = false;
    }
  }
  
  /**
   * 加载热榜Tab数据 (按点赞数排序)
   */
  private async loadHotList(reset: boolean): Promise<void> {
    if (this.isLoadingHot) return;
    
    if (reset) {
      this.hotPage = 1;
      this.hotTotalPages = 1;
    }
    
    this.isLoadingHot = true;
    this.hotError = '';
    
    try {
      const apiService = APIService.getInstance();
      const result: object = await apiService.fetchRecipes(
        this.hotPage,
        this.pageSize,
        '',
        'likes' // 按点赞数排序
      );
      
      const response: RecipesResponse = result as RecipesResponse;
      const newRecipes: Array<Recipe> = response.recipes || [];
      
      if (reset) {
        this.hotDataSource.setData(newRecipes);
        // 刷新时更新版本号，强制LazyForEach重新渲染
        this.hotDataVersion++;
      } else {
        this.hotDataSource.addData(newRecipes);
      }
      
      this.hotPage = response.currentPage + 1;
      this.hotTotalPages = response.totalPages;
      
      console.info(`[RecommendationsPage] 热榜加载成功: ${newRecipes.length}条`);
    } catch (error) {
      console.error('[RecommendationsPage] 热榜加载失败:', error);
      this.hotError = '加载失败，请稍后重试';
    } finally {
      this.isLoadingHot = false;
    }
  }
  
  /**
   * 加载更多数据
   */
  private loadMore(): void {
    if (this.currentTab === TabType.RECOMMENDATION) {
      if (this.recommendPage <= this.recommendTotalPages && !this.isLoadingRecommend) {
        this.loadRecommendations(false);
      }
    } else if (this.currentTab === TabType.HOT) {
      if (this.hotPage <= this.hotTotalPages && !this.isLoadingHot) {
        this.loadHotList(false);
      }
    }
  }
  
  /**
   * 切换Tab
   */
  private onTabChange(index: number): void {
    this.selectedTabIndex = index;
    this.currentTab = index as TabType;
    
    // 切换到热榜且未加载数据时，加载数据
    if (this.currentTab === TabType.HOT && this.hotDataSource.totalCount() === 0) {
      this.loadHotList(true);
    }
  }
  
  /**
   * 下拉刷新 - 推荐Tab
   */
  private async onRefreshRecommend(): Promise<void> {
    console.info('[RecommendationsPage] 推荐Tab下拉刷新开始');
    this.isRefreshingRecommend = true;
    
    try {
      // 重置页码并重新加载第一页
      await this.loadRecommendations(true);
    } finally {
      this.isRefreshingRecommend = false;
      console.info('[RecommendationsPage] 推荐Tab下拉刷新完成');
    }
  }
  
  /**
   * 下拉刷新 - 热榜Tab
   */
  private async onRefreshHot(): Promise<void> {
    console.info('[RecommendationsPage] 热榜Tab下拉刷新开始');
    this.isRefreshingHot = true;
    
    try {
      // 重置页码并重新加载第一页
      await this.loadHotList(true);
    } finally {
      this.isRefreshingHot = false;
      console.info('[RecommendationsPage] 热榜Tab下拉刷新完成');
    }
  }
  
  /**
   * 跳转到配方详情
   */
  private openRecipeDetail(recipeId: string): void {
    router.pushUrl({
      url: 'pages/RecipeDetailPage',
      params: { recipeId: recipeId }
    });
  }
  
  build() {
    Column() {
      // 顶部Tab导航栏
      this.buildTabBar()
      
      // 内容区域 - 根据当前Tab显示不同内容
      if (this.currentTab === TabType.RECOMMENDATION) {
        this.buildRecommendContent()
      } else {
        this.buildHotContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
  }
  
  private goToSearch(): void {
    router.pushUrl({
      url: 'pages/SearchPage'
    });
  }

  /**
   * 顶部Tab导航栏
   */
  @Builder
  buildTabBar() {
    Column() {
      // Tab标签行
      Row() {
        // 推荐Tab
        Column() {
          Text('推荐')
            .fontSize(this.selectedTabIndex === 0 ? 18 : 16)
            .fontWeight(this.selectedTabIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedTabIndex === 0 ? this.getColors().textPrimary : this.getColors().textTertiary)
            .animation({
              duration: 200,
              curve: Curve.EaseInOut
            })
          
          // 底部指示器
          if (this.selectedTabIndex === 0) {
            Divider()
              .width(24)
              .height(3)
              .color(this.getColors().accent)
              .borderRadius(1.5)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onTabChange(0))
        
        // 热榜Tab
        Column() {
          Text('热榜')
            .fontSize(this.selectedTabIndex === 1 ? 18 : 16)
            .fontWeight(this.selectedTabIndex === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedTabIndex === 1 ? this.getColors().textPrimary : this.getColors().textTertiary)
            .animation({
              duration: 200,
              curve: Curve.EaseInOut
            })
          
          // 底部指示器
          if (this.selectedTabIndex === 1) {
            Divider()
              .width(24)
              .height(3)
              .color(this.getColors().accent)
              .borderRadius(1.5)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onTabChange(1))
        
        // 搜索图标
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([this.getColors().textPrimary])
          .margin({ right: 6 })
          .onClick(() => this.goToSearch())
      }
      .width('100%')
      .height(50)
      .padding({ left: 16, right: 16 })
      
      // 分割线
      Divider()
        .color(this.getColors().divider)
        .strokeWidth(1)
    }
    .width('100%')
    .backgroundColor(this.getColors().cardBackground)
  }
  
  /**
   * 推荐Tab内容
   */
  @Builder
  buildRecommendContent() {
    if (this.recommendDataSource.totalCount() === 0 && !this.isLoadingRecommend) {
      // 显示空状态或提示信息
      this.buildEmptyState('推荐', this.recommendMessage)
    } else {
      Refresh({ refreshing: $$this.isRefreshingRecommend }) {
        WaterFlow({ footer: () => { this.buildFooter(this.isLoadingRecommend, this.recommendPage > this.recommendTotalPages) } }) {
          LazyForEach(this.recommendDataSource, (recipe: RecommendedRecipe, index: number) => {
            FlowItem() {
              RecommendedRecipeCard({
                recipe: recipe,
                cardRatio: this.getCardRatio(index),
                showMatchPercentage: this.showMatchPercentage,
                showRecommendReason: this.showRecommendReason,
                onTap: () => { this.openRecipeDetail(recipe.id) }
              })
            }
            .width('100%')
          }, (recipe: RecommendedRecipe, index: number) => `${this.recommendDataVersion}_${recipe.id}_${index}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .width('100%')
      .layoutWeight(1)
      .onRefreshing(async () => {
        await this.onRefreshRecommend();
      })
    }
  }
  
  /**
   * 热榜Tab内容
   */
  @Builder
  buildHotContent() {
    if (this.hotDataSource.totalCount() === 0 && !this.isLoadingHot) {
      this.buildEmptyState('热榜')
    } else {
      Refresh({ refreshing: $$this.isRefreshingHot }) {
        WaterFlow({ footer: () => { this.buildFooter(this.isLoadingHot, this.hotPage > this.hotTotalPages) } }) {
          LazyForEach(this.hotDataSource, (recipe: Recipe, index: number) => {
            FlowItem() {
              RecipeWaterfallCard({
                recipe: recipe,
                cardRatio: this.getCardRatio(index),
                showRank: true,
                rank: index + 1,
                onTap: () => { this.openRecipeDetail(recipe.id) }
              })
            }
            .width('100%')
          }, (recipe: Recipe, index: number) => `${this.hotDataVersion}_${recipe.id}_${index}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .width('100%')
      .layoutWeight(1)
      .onRefreshing(async () => {
        await this.onRefreshHot();
      })
    }
  }
  
  /**
   * 空状态
   */
  @Builder
  buildEmptyState(tabName: string, message?: string) {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(64)
        .fontColor(['#CCCCCC'])
      
      Text(message || `暂无${tabName}内容`)
        .fontSize(16)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
        .padding({ left: 20, right: 20 })
      
      Button('刷新')
        .fontSize(14)
        .backgroundColor('#007DFF')
        .borderRadius(20)
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        .margin({ top: 16 })
        .onClick(() => {
          if (this.currentTab === TabType.RECOMMENDATION) {
            this.loadRecommendations(true);
          } else {
            this.loadHotList(true);
          }
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 底部加载状态
   */
  @Builder
  buildFooter(isLoading: boolean, isEnd: boolean): void {
    Row() {
      if (isLoading) {
        LoadingProgress().width(20).height(20).margin({ right: 8 })
        Text('加载中...').fontSize(14).fontColor('#999999')
      } else if (isEnd) {
        Text('没有更多了').fontSize(14).fontColor('#999999')
      }
    }
    .width('100%')
    .height(50)
    .justifyContent(FlexAlign.Center)
  }
  
  /**
   * 获取卡片比例 (3:4 和 1:1 混合)
   */
  private getCardRatio(index: number): number {
    // 每4个卡片中，前2个使用3:4，后2个使用1:1
    const pattern = index % 4;
    return (pattern === 0 || pattern === 1) ? 0.75 : 1.0; // 3:4 = 0.75, 1:1 = 1.0
  }
}

/**
 * 推荐卡片组件 - 带匹配度和推荐理由
 */
@Component
struct RecommendedRecipeCard {
  @Prop recipe: RecommendedRecipe;
  @Prop cardRatio: number = 0.75; // 默认3:4比例
  @Prop showMatchPercentage: boolean = true; // 是否显示匹配度标签
  @Prop showRecommendReason: boolean = true; // 是否显示推荐理由
  @State imageLoadError: boolean = false;
  onTap?: () => void;
  
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
  
  build() {
    Column() {
      // 图片区域
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.getImageSource())
          .width('100%')
          .aspectRatio(this.cardRatio) // 动态宽高比
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .alt($r('app.media.wine'))
          .onError(() => {
            this.imageLoadError = true;
          })
        
        // 匹配度标签（右上角）
        if (this.showMatchPercentage && this.recipe.matchPercentage > 0) {
          Row({ space: 2 }) {
            Text(`${this.recipe.matchPercentage}%`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('匹配')
              .fontSize(10)
              .fontColor(Color.White)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.getMatchColor(this.recipe.matchPercentage))
          .borderRadius({ topRight: 8, bottomLeft: 8 })
        }
      }
      .width('100%')
      
      // 内容区域
      Column() {
        // 标题
        Text(this.recipe.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor('#333')
          .width('100%')
          .textAlign(TextAlign.Start)
        
        // 推荐理由（酒品名称下方）
        if (this.showRecommendReason && this.recipe.reason) {
          Text(this.recipe.reason)
            .fontSize(10)
            .fontColor('#666')
            .width('100%')
            .margin({ top: 4 })
            .lineHeight(14)
        }
        
        // ABV标签和点赞数（同一行）
        Row({ space: 8 }) {
          // ABV标签
          if (this.recipe.estimatedAbv !== undefined && this.recipe.estimatedAbv !== null) {
            Text(`${Math.round(Number(this.recipe.estimatedAbv))}%`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF6B00')
              .backgroundColor('#FFF0E0')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .flexShrink(0)
          }
          
          Blank()
          
          // 点赞数（右下角）
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.heart'))
              .fontSize(12)
              .fontColor(['#666'])
            Text(`${this.recipe.likeCount || 0}`)
              .fontSize(12)
              .fontColor('#666')
          }
          .flexShrink(0)
        }
        .margin({ top: 6 })
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .padding(8)
      .backgroundColor(Color.White)
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .borderRadius(8)
    .backgroundColor(Color.White)
    .shadow({ radius: 4, color: '#1A000000', offsetY: 2 })
    .onClick(() => {
      if (this.onTap) this.onTap();
    })
  }
  
  /**
   * 获取匹配度颜色
   */
  private getMatchColor(percentage: number): string {
    if (percentage >= 80) {
      return '#4CAF50'; // 绿色 - 高匹配
    } else if (percentage >= 60) {
      return '#FF9800'; // 橙色 - 中等匹配
    } else {
      return '#9E9E9E'; // 灰色 - 低匹配
    }
  }
}

/**
 * 瀑布流卡片组件 - 参考RecipesPage的RecipeCard
 */
@Component
struct RecipeWaterfallCard {
  @Prop recipe: Recipe;
  @Prop cardRatio: number = 0.75; // 默认3:4比例
  @Prop showRank: boolean = false; // 是否显示排名
  @Prop rank: number = 0; // 排名数字
  @State imageLoadError: boolean = false;
  onTap?: () => void;
  
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
  
  build() {
    Column() {
      // 图片区域
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.getImageSource())
          .width('100%')
          .aspectRatio(this.cardRatio) // 动态宽高比
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .alt($r('app.media.wine'))
          .onError(() => {
            this.imageLoadError = true;
          })
        
        // 热榜排名标签
        if (this.showRank && this.rank > 0 && this.rank <= 3) {
          Row() {
            Text(`${this.rank}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getRankColor(this.rank))
          .borderRadius({ topLeft: 8, bottomRight: 8 })
        } else if (this.showRank && this.rank > 0) {
          Row() {
            Text(`${this.rank}`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .borderRadius({ topLeft: 8, bottomRight: 8 })
        }
      }
      .width('100%')
      
      // 内容区域
      Column() {
        // 标题
        Text(this.recipe.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor('#333')
          .width('100%')
          .textAlign(TextAlign.Start)
        
        // ABV标签和配料预览
        Row({ space: 4 }) {
          Text(`${this.recipe.estimatedAbv.toFixed(0)}%`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF6B00')
            .backgroundColor('#FFF0E0')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .flexShrink(0)
          
          // 配料预览
          if (this.recipe.ingredients && typeof this.recipe.ingredients === 'string') {
            Text(this.recipe.ingredients.split(',').slice(0, 3).join(' '))
              .fontSize(10)
              .fontColor('#999')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .margin({ top: 6 })
        .width('100%')
        
        // 底部信息
        Row() {
          // 创建者
          Row({ space: 4 }) {
            Image($r('app.media.startIcon'))
              .width(16)
              .height(16)
              .borderRadius(8)
              .flexShrink(0)
            
            Text(this.recipe.createdBy)
              .fontSize(10)
              .fontColor('#666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          
          // 点赞数
          Row({ space: 2 }) {
            SymbolGlyph(this.recipe.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(12)
              .fontColor([this.recipe.isLiked ? '#FF4D4F' : '#666'])
            Text(`${this.recipe.likeCount}`)
              .fontSize(12)
              .fontColor('#666')
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
      .backgroundColor(Color.White)
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .borderRadius(8)
    .backgroundColor(Color.White)
    .shadow({ radius: 4, color: '#1A000000', offsetY: 2 })
    .onClick(() => {
      if (this.onTap) this.onTap();
    })
  }
  
  /**
   * 获取排名颜色
   */
  private getRankColor(rank: number): string {
    switch (rank) {
      case 1:
        return '#FFD700'; // 金色
      case 2:
        return '#C0C0C0'; // 银色
      case 3:
        return '#CD7F32'; // 铜色
      default:
        return 'rgba(0, 0, 0, 0.5)';
    }
  }
}
