// SearchPage.ets - 搜索页面
// 参考 Swift SearchView.swift 和 server.js /api/recipes 实现
// 支持按配方名称搜索,搜索历史,分页加载

import { Recipe } from '../models/Recipe';
import APIService from '../services/APIService';
import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';
import preferences from '@ohos.data.preferences';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

// 搜索历史最大条数
const MAX_HISTORY_COUNT = 10;
const SEARCH_HISTORY_KEY = 'search_history';
const PREFERENCES_NAME = 'searchPreferences';

@Entry
@Component
export struct SearchPage {
  // 深色模式支持
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  // 允许从外部绑定(用于 Tab 导航),也可以独立使用
  @State searchText: string = '';
  @State recipes: Array<Recipe> = [];
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State hasError: boolean = false;
  @State errorMessage: string = '';
  @State searchHistory: Array<string> = [];
  @State hasSearched: boolean = false; // 是否已执行搜索
  
  // 可选的关闭回调(用于嵌入模式)
  onClose?: () => void;
  
  private readonly pageSize: number = 20;
  private preferencesInstance: preferences.Preferences | null = null;
  
  aboutToAppear() {
    console.info('[SearchPage] ========================================');
    console.info('[SearchPage] Page appeared (aboutToAppear)');
    console.info('[SearchPage] ========================================');
    
    // 加载搜索历史
    this.loadSearchHistory();
  }
  
  /**
   * 加载搜索历史
   */
  private async loadSearchHistory() {
    try {
      const context = getContext(this);
      this.preferencesInstance = await preferences.getPreferences(context, PREFERENCES_NAME);
      const historyStr = await this.preferencesInstance.get(SEARCH_HISTORY_KEY, '[]') as string;
      this.searchHistory = JSON.parse(historyStr) as Array<string>;
      console.info('[SearchPage] Loaded search history:', this.searchHistory.length, 'items');
    } catch (error) {
      console.error('[SearchPage] Failed to load search history:', error);
      this.searchHistory = [];
    }
  }
  
  /**
   * 保存搜索历史
   */
  private async saveSearchHistory() {
    try {
      if (this.preferencesInstance) {
        await this.preferencesInstance.put(SEARCH_HISTORY_KEY, JSON.stringify(this.searchHistory));
        await this.preferencesInstance.flush();
        console.info('[SearchPage] Saved search history');
      }
    } catch (error) {
      console.error('[SearchPage] Failed to save search history:', error);
    }
  }
  
  /**
   * 添加搜索历史
   */
  private addToHistory(keyword: string) {
    if (!keyword.trim()) return;
    
    // 移除已存在的相同记录
    const index = this.searchHistory.indexOf(keyword);
    if (index !== -1) {
      this.searchHistory.splice(index, 1);
    }
    
    // 添加到开头
    this.searchHistory.unshift(keyword);
    
    // 限制最大条数
    if (this.searchHistory.length > MAX_HISTORY_COUNT) {
      this.searchHistory = this.searchHistory.slice(0, MAX_HISTORY_COUNT);
    }
    
    this.saveSearchHistory();
  }
  
  /**
   * 删除单条搜索历史
   */
  private removeFromHistory(keyword: string) {
    const index = this.searchHistory.indexOf(keyword);
    if (index !== -1) {
      this.searchHistory.splice(index, 1);
      this.saveSearchHistory();
    }
  }
  
  /**
   * 清空搜索历史
   */
  private clearHistory() {
    this.searchHistory = [];
    this.saveSearchHistory();
  }
  
  /**
   * 执行搜索
   */
  private doSearch() {
    const query = this.searchText.trim();
    if (query === '') {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }
    
    console.info(`[SearchPage] doSearch - query: "${query}"`);
    this.addToHistory(query);
    this.hasSearched = true;
    this.fetchRecipes(true);
  }
  
  /**
   * 使用历史记录搜索
   */
  private searchWithHistory(keyword: string) {
    this.searchText = keyword;
    this.doSearch();
  }
  
  /**
   * 获取搜索结果
   * @param reset 是否重置列表(重新搜索)
   */
  private async fetchRecipes(reset: boolean) {
    const query = this.searchText.trim();
    
    console.info(`[SearchPage] ========== fetchRecipes START ==========`);
    console.info(`[SearchPage] Query: "${query}", Reset: ${reset}, CurrentPage: ${this.currentPage}`);
    
    if (query === '') {
      console.info(`[SearchPage] Query is empty, clearing results`);
      this.recipes = [];
      return;
    }
    
    if (reset) {
      console.info(`[SearchPage] Resetting search - clearing recipes and setting page to 1`);
      this.currentPage = 1;
      this.recipes = [];
    }
    
    this.isLoading = true;
    this.hasError = false;
    this.errorMessage = '';
    
    try {
      console.info(`[SearchPage] Calling API - page: ${this.currentPage}, limit: ${this.pageSize}, query: "${query}"`);
      
      const apiService = APIService.getInstance();
      const result: object = await apiService.fetchRecipes(
        this.currentPage,
        this.pageSize,
        query,
        'created'  // 使用 'created' 排序，与Swift版本一致
      );
      
      console.info(`[SearchPage] API call succeeded, parsing response...`);
      
      // 解析响应
      const recipesData = Reflect.get(result, 'recipes') as Array<object>;
      const totalPages = Reflect.get(result, 'totalPages') as number;
      const currentPage = Reflect.get(result, 'currentPage') as number;
      
      console.info(`[SearchPage] Parsed data - recipes count: ${recipesData?.length || 0}`);
      
      if (recipesData && Array.isArray(recipesData)) {
        const newRecipes = this.parseRecipesData(recipesData);
        
        if (reset) {
          this.recipes = newRecipes;
        } else {
          this.recipes = this.recipes.concat(newRecipes);
        }
        
        this.totalPages = totalPages || 1;
        this.currentPage = currentPage || 1;
        
        console.info(`[SearchPage] Success - total recipes: ${this.recipes.length}`);
        
        // Fallback: 如果是首次搜索且结果为空，尝试拉取所有数据在本地过滤
        if (reset && newRecipes.length === 0 && query !== '') {
          console.info(`[SearchPage] No results from server, trying local filter fallback...`);
          await this.fetchAndFilterLocally(query);
        }
      }
      
    } catch (error) {
      console.error('[SearchPage] ========== Search FAILED ==========');
      console.error('[SearchPage] Error:', error);
      console.error('[SearchPage] Error message:', error instanceof Error ? error.message : String(error));
      
      // 如果服务器搜索失败（比如500错误），尝试fallback方案
      if (reset && error instanceof Error && error.message.includes('500')) {
        console.info(`[SearchPage] Server search failed (500), trying local filter fallback...`);
        try {
          await this.fetchAndFilterLocally(query);
          return; // 成功则返回，不显示错误
        } catch (fallbackError) {
          console.error('[SearchPage] Fallback also failed:', fallbackError);
        }
      }
      
      this.hasError = true;
      this.errorMessage = this.formatErrorMessage(error);
      
      promptAction.showToast({ 
        message: '搜索失败，请查看详情',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
      console.info(`[SearchPage] ========== fetchRecipes END ==========`);
    }
  }
  
  /**
   * Fallback方案：拉取所有数据并在本地过滤
   * 参考Swift SearchView的fetchFallbackAllAndFilter方法
   */
  private async fetchAndFilterLocally(query: string) {
    console.info(`[SearchPage] fetchAndFilterLocally - query: "${query}"`);
    
    try {
      const apiService = APIService.getInstance();
      // 拉取所有数据（不带搜索条件）
      const result: object = await apiService.fetchRecipes(
        1,
        100,  // 拉取较多数据用于本地过滤
        '',   // 空搜索词
        'created'
      );
      
      const allRecipes = Reflect.get(result, 'recipes') as Array<object>;
      
      if (allRecipes && Array.isArray(allRecipes)) {
        console.info(`[SearchPage] Got ${allRecipes.length} recipes for local filtering`);
        
        const parsedRecipes = this.parseRecipesData(allRecipes);
        
        // 本地过滤：按名称或创建者匹配（不区分大小写）
        const queryLower = query.toLowerCase();
        const filtered = parsedRecipes.filter((recipe: Recipe) => {
          const nameMatch = recipe.name.toLowerCase().includes(queryLower);
          const creatorMatch = recipe.createdBy.toLowerCase().includes(queryLower);
          return nameMatch || creatorMatch;
        });
        
        console.info(`[SearchPage] Local filter found ${filtered.length} matching recipes`);
        
        this.recipes = filtered;
        this.currentPage = 1;
        this.totalPages = 1;
        this.hasError = false;
      }
    } catch (err) {
      console.error('[SearchPage] fetchAndFilterLocally failed:', err);
      // ArkTS不允许throw任意类型，需要转换为Error
      if (err instanceof Error) {
        throw err;
      } else {
        throw new Error('本地过滤失败');
      }
    }
  }
  
  /**
   * 解析配方数据数组
   */
  private parseRecipesData(recipesData: Array<object>): Array<Recipe> {
    return recipesData.map((item: object): Recipe => {
      const id = Reflect.get(item, 'id') as string;
      const name = Reflect.get(item, 'name') as string;
      const createdBy = Reflect.get(item, 'createdBy') as string;
      const estimatedAbvValue = Reflect.get(item, 'estimatedAbv') as string | number | object | null;
      const likeCountValue = Reflect.get(item, 'likeCount') as string | number | object | null;
      const favoriteCountValue = Reflect.get(item, 'favoriteCount') as string | number | object | null;
      const ingredients = Reflect.get(item, 'ingredients') as string;
      
      return {
        id: id,
        name: name,
        createdBy: createdBy,
        instructions: Reflect.get(item, 'instructions') as string,
        estimatedAbv: this.parseNumber(estimatedAbvValue),
        likeCount: this.parseNumber(likeCountValue),
        favoriteCount: this.parseNumber(favoriteCountValue),
        ingredients: ingredients
      };
    });
  }
  
  /**
   * 格式化错误消息
   */
  private formatErrorMessage(error: Error | object): string {
    if (!(error instanceof Error)) {
      return '搜索失败，请重试';
    }
    
    const msg = error.message;
    
    if (msg.includes('500')) {
      return '服务器内部错误 (500)\n\n已尝试本地过滤但仍失败\n请稍后重试';
    } else if (msg.includes('404')) {
      return 'API接口未找到 (404)\n\n请检查服务器配置';
    } else if (msg.includes('NETWORK_ERROR') || msg.includes('网络')) {
      return '网络连接失败\n\n请检查：\n• 设备网络连接\n• 服务器是否在线';
    } else if (msg.includes('timeout') || msg.includes('超时')) {
      return '请求超时\n\n请检查网络连接速度';
    } else {
      return `${msg}\n\n请重试或查看日志`;
    }
  }
  
  /**
   * 加载更多
   */
  private loadMore() {
    console.info(`[SearchPage] loadMore called - isLoading: ${this.isLoading}, currentPage: ${this.currentPage}, totalPages: ${this.totalPages}`);
    
    if (this.isLoading) {
      console.info(`[SearchPage] Already loading, skipping loadMore`);
      return;
    }
    
    if (this.currentPage >= this.totalPages) {
      console.info(`[SearchPage] Already at last page, skipping loadMore`);
      return;
    }
    
    console.info(`[SearchPage] Loading more - incrementing page from ${this.currentPage} to ${this.currentPage + 1}`);
    this.currentPage++;
    this.fetchRecipes(false);
  }
  
  /**
   * 安全地解析数值
   */
  private parseNumber(value: string | number | object | null): number {
    if (value === null || value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? 0 : parsed;
    }
    const parsed = parseFloat(String(value));
    return isNaN(parsed) ? 0 : parsed;
  }
  
  /**
   * 跳转到配方详情
   */
  private navigateToDetail(recipe: Recipe) {
    router.pushUrl({
      url: 'pages/RecipeDetailPage',
      params: {
        recipeId: recipe.id
      }
    }).catch((error: Error) => {
      console.error('[SearchPage] Navigation failed:', error);
      promptAction.showToast({ message: '跳转失败' });
    });
  }
  
  build() {
    Column() {
      // 顶部搜索栏
      this.buildSearchBar();
      
      // 内容区域
      if (!this.hasSearched) {
        // 未搜索状态 - 显示搜索历史
        this.buildHistoryState();
      } else if (this.isLoading && this.recipes.length === 0) {
        // 首次加载状态
        this.buildLoadingState();
      } else if (this.hasError) {
        // 错误状态
        this.buildErrorState();
      } else if (this.recipes.length === 0) {
        // 无搜索结果
        this.buildNoResultsState();
      } else {
        // 搜索结果列表
        this.buildResultsList();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
  }
  
  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Row() {
      // 返回按钮
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([this.getColors().textPrimary])
      }
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .height(44)
      .width(44)
      .onClick(() => {
        // 如果有关闭回调则调用,否则返回上一页
        if (this.onClose) {
          this.onClose();
        } else {
          router.back();
        }
      })
      
      // 搜索输入框
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([this.getColors().textTertiary])
          .margin({ right: 8 })
        
        TextInput({ 
          placeholder: '搜索配方名称...',
          text: $$this.searchText 
        })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Color.Transparent)
          .fontColor(this.getColors().textPrimary)
          .border({ width: 0 })
          .onSubmit(() => {
            console.info(`[SearchPage] TextInput onSubmit - searchText: "${this.searchText}"`);
            this.doSearch();
          })
        
        // 清除按钮
        if (this.searchText.length > 0) {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([this.getColors().textTertiary])
          }
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .width(32)
          .height(32)
          .onClick(() => {
            this.searchText = '';
            this.recipes = [];
            this.hasSearched = false;
            this.hasError = false;
          })
        }
      }
      .layoutWeight(1)
      .height(40)
      .backgroundColor(this.getColors().inputBackground)
      .borderRadius(20)
      .padding({ left: 12, right: 4 })
      
      // 搜索按钮
      Button('搜索')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#007DFF')
        .height(36)
        .borderRadius(18)
        .padding({ left: 16, right: 16 })
        .margin({ left: 8 })
        .onClick(() => {
          this.doSearch();
        })
    }
    .width('100%')
    .height(60)
    .padding({ left: 8, right: 12 })
    .backgroundColor(this.getColors().cardBackground)
    .shadow({
      radius: 4,
      color: this.isDarkMode ? '#00000030' : '#00000008',
      offsetX: 0,
      offsetY: 2
    })
  }
  
  /**
   * 构建搜索历史状态
   */
  @Builder
  buildHistoryState() {
    Column() {
      if (this.searchHistory.length > 0) {
        // 历史记录头部
        Row() {
          Text('搜索历史')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().textPrimary)
          
          Blank()
          
          Button() {
            Text('清空')
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
          }
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearHistory();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })
        
        // 历史记录列表
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (keyword: string) => {
            Row({ space: 4 }) {
              Text(keyword)
                .fontSize(14)
                .fontColor(this.getColors().textSecondary)
                .layoutWeight(1)
                .onClick(() => {
                  this.searchWithHistory(keyword);
                })
              
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([this.getColors().textTertiary])
                .padding({ left: 8, right: 4 })
                .onClick(() => {
                  this.removeFromHistory(keyword);
                })
            }
            .height(32)
            .padding({ left: 12, right: 8 })
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(this.getColors().secondaryBackground)
            .borderRadius(16)
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      } else {
        // 无历史记录
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(64)
            .fontColor([this.getColors().textTertiary])
          
          Text('输入关键词搜索配方')
            .fontSize(16)
            .fontColor(this.getColors().textSecondary)
          
          Text('搜索建议:')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
            .margin({ top: 24 })
          
          Column({ space: 8 }) {
            Text('• 输入配方名称')
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
            Text('• 支持模糊搜索')
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(32)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  /**
   * 构建空状态（已废弃，由 buildHistoryState 替代）
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(64)
        .fontColor(['#CCCCCC'])
      
      Text('输入关键词搜索配方')
        .fontSize(16)
        .fontColor('#999999')
      
      Text('搜索建议:')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 24 })
      
      Column({ space: 8 }) {
        Text('• 输入配方名称')
          .fontSize(14)
          .fontColor('#999999')
        Text('• 支持模糊搜索')
          .fontSize(14)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 构建加载状态
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(50)
        .height(50)
        .color('#1890ff')
      
      Text('搜索中...')
        .fontSize(14)
        .fontColor(this.getColors().textTertiary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
  
  /**
   * 构建错误状态
   */
  @Builder
  buildErrorState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(64)
        .fontColor(['#FF3B30'])
      
      Text(this.errorMessage || '搜索失败')
        .fontSize(14)
        .fontColor('#FF3B30')
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .padding({ left: 20, right: 20 })
      
      // 提示信息卡片
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(14)
            .fontColor(['#666666'])
          Text('提示')
            .fontSize(12)
            .fontColor('#666666')
            .fontWeight(FontWeight.Bold)
        }
        
        Column({ space: 4 }) {
          Text('• 已尝试使用本地过滤方案')
            .fontSize(11)
            .fontColor('#999999')
          
          Text('• 点击"重试"按钮再次尝试')
            .fontSize(11)
            .fontColor('#999999')
          
          Text(`• 搜索词: "${this.searchText}"`)
            .fontSize(11)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
      .width('90%')
      .padding(12)
      .backgroundColor('#F0F9FF')
      .borderRadius(8)
      .margin({ top: 12 })
      
      Row({ space: 12 }) {
        Button('重试')
          .fontSize(14)
          .backgroundColor('#1890ff')
          .borderRadius(20)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => {
            console.info('[SearchPage] User clicked retry button');
            this.fetchRecipes(true);
          })
      }
      .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 构建无结果状态
   */
  @Builder
  buildNoResultsState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(64)
        .fontColor([this.getColors().textTertiary])
      
      Text(`未找到"${this.searchText}"相关的配方`)
        .fontSize(16)
        .fontColor(this.getColors().textSecondary)
        .textAlign(TextAlign.Center)
      
      Text('试试其他关键词吧')
        .fontSize(14)
        .fontColor(this.getColors().textTertiary)
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 构建搜索结果列表
   */
  @Builder
  buildResultsList() {
    Column() {
      // 结果统计
      Row() {
        Text(`找到 ${this.recipes.length} 个配方`)
          .fontSize(14)
          .fontColor(this.getColors().textSecondary)
        
        if (this.currentPage < this.totalPages) {
          Text(` (第 ${this.currentPage}/${this.totalPages} 页)`)
            .fontSize(12)
            .fontColor(this.getColors().textTertiary)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      
      // 结果列表
      List({ space: 12 }) {
        ForEach(this.recipes, (recipe: Recipe, index: number) => {
          ListItem() {
            this.buildRecipeCard(recipe)
          }
          .onClick(() => {
            this.navigateToDetail(recipe);
          })
          .onAppear(() => {
            // 滚动到倒数第3个时触发加载更多
            if (index === this.recipes.length - 3) {
              this.loadMore();
            }
          })
        }, (recipe: Recipe) => recipe.id)
        
        // 加载更多指示器
        if (this.isLoading && this.recipes.length > 0) {
          ListItem() {
            Row() {
              LoadingProgress()
                .width(30)
                .height(30)
                .color('#1890ff')
              Text('加载中...')
                .fontSize(14)
                .fontColor(this.getColors().textTertiary)
                .margin({ left: 12 })
            }
            .width('100%')
            .height(60)
            .justifyContent(FlexAlign.Center)
          }
        }
        
        // 已加载全部
        if (!this.isLoading && this.currentPage >= this.totalPages && this.recipes.length > 0) {
          ListItem() {
            Text('已显示全部结果')
              .fontSize(12)
              .fontColor(this.getColors().textTertiary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 16, bottom: 16 })
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .layoutWeight(1)
    .width('100%')
  }
  
  /**
   * 构建配方卡片
   */
  @Builder
  buildRecipeCard(recipe: Recipe) {
    Column({ space: 12 }) {
      // 标题和创建者
      Column({ space: 6 }) {
        Text(recipe.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Row({ space: 12 }) {
          Text(`👤 ${recipe.createdBy}`)
            .fontSize(13)
            .fontColor(this.getColors().textSecondary)
          
          Text('|')
            .fontSize(13)
            .fontColor(this.getColors().divider)
          
          Text(`${recipe.estimatedAbv.toFixed(1)}% ABV`)
            .fontSize(13)
            .fontColor('#1890ff')
            .fontWeight(FontWeight.Medium)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      
      // 分隔线
      Divider()
        .color(this.getColors().divider)
      
      // 底部信息
      Row() {
        // 原料信息
        if (recipe.ingredients && typeof recipe.ingredients === 'string') {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.list_bullet'))
              .fontSize(14)
              .fontColor([this.getColors().textTertiary])
            Text(`${recipe.ingredients.split(',').length} 种原料`)
              .fontSize(12)
              .fontColor(this.getColors().textTertiary)
          }
        }
        
        Blank()
        
        // 互动信息
        Row({ space: 16 }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(14)
              .fontColor(['#FF3B30'])
            Text(recipe.likeCount.toString())
              .fontSize(12)
              .fontColor(this.getColors().textTertiary)
          }
          
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(14)
              .fontColor(['#FFB800'])
            Text(recipe.favoriteCount.toString())
              .fontSize(12)
              .fontColor(this.getColors().textTertiary)
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBackground)
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: this.isDarkMode ? '#00000030' : '#00000010',
      offsetX: 0,
      offsetY: 2
    })
  }
}
