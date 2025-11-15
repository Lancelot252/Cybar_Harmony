// SearchPage.ets - 搜索页面
// 参考 Swift SearchView.swift 和 server.js /api/recipes 实现
// 支持按配方名称搜索,实时搜索,分页加载

import { Recipe } from '../models/Recipe';
import APIService from '../services/APIService';
import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';

@Entry
@Component
export struct SearchPage {
  // 允许从外部绑定(用于 Tab 导航),也可以独立使用
  @State searchText: string = '';
  @State recipes: Array<Recipe> = [];
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State hasError: boolean = false;
  @State errorMessage: string = '';
  
  // 可选的关闭回调(用于嵌入模式)
  onClose?: () => void;
  
  // 防抖定时器
  private debounceTimer: number = -1;
  private readonly pageSize: number = 20;
  private readonly debounceDelay: number = 300; // 300ms 防抖延迟
  
  aboutToAppear() {
    console.info('[SearchPage] ========================================');
    console.info('[SearchPage] Page appeared (aboutToAppear)');
    console.info('[SearchPage] Initial state - searchText: "%s"', this.searchText);
    console.info('[SearchPage] Initial state - recipes.length: %d', this.recipes.length);
    console.info('[SearchPage] ========================================');
    
    // 测试API连接
    this.testAPIConnection();
  }
  
  /**
   * 测试API连接
   */
  private async testAPIConnection() {
    try {
      console.info('[SearchPage] Testing API connection...');
      const apiService = APIService.getInstance();
      
      // 尝试获取第一页数据来测试连接
      await apiService.fetchRecipes(1, 1, '', 'default');
      console.info('[SearchPage] API connection test PASSED ✓');
    } catch (error) {
      console.error('[SearchPage] API connection test FAILED ✗');
      console.error('[SearchPage] Error:', error);
      
      // 不显示错误给用户，因为这只是预检测
      // 用户搜索时会看到实际错误
    }
  }
  
  aboutToDisappear() {
    console.info('[SearchPage] ========================================');
    console.info('[SearchPage] Page disappearing (aboutToDisappear)');
    
    // 清理定时器
    if (this.debounceTimer !== -1) {
      console.info('[SearchPage] Cleaning up debounce timer');
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    
    console.info('[SearchPage] Page cleanup complete');
    console.info('[SearchPage] ========================================');
  }
  
  /**
   * 执行搜索 (带防抖)
   */
  private performSearch() {
    console.info(`[SearchPage] performSearch called - searchText: "${this.searchText}"`);
    
    // 清除之前的定时器
    if (this.debounceTimer !== -1) {
      console.info(`[SearchPage] Clearing previous debounce timer`);
      clearTimeout(this.debounceTimer);
    }
    
    // 如果搜索框为空,清空结果
    if (this.searchText.trim() === '') {
      console.info(`[SearchPage] Search text is empty, clearing results`);
      this.recipes = [];
      this.currentPage = 1;
      this.totalPages = 1;
      this.hasError = false;
      return;
    }
    
    // 设置新的防抖定时器
    console.info(`[SearchPage] Setting debounce timer for ${this.debounceDelay}ms`);
    this.debounceTimer = setTimeout(() => {
      console.info(`[SearchPage] Debounce timer fired, executing search`);
      this.fetchRecipes(true);
    }, this.debounceDelay);
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
      if (this.searchText.trim() === '') {
        // 空状态 - 搜索提示
        this.buildEmptyState();
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
    .backgroundColor('#F5F5F5')
  }
  
  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Row() {
      // 返回按钮
      Button() {
        Row({ space: 4 }) {
          Text('←')
            .fontSize(24)
            .fontColor('#333333')
          Text('返回')
            .fontSize(16)
            .fontColor('#333333')
        }
      }
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .height(44)
      .padding({ left: 4, right: 12 })
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
        Text('🔍')
          .fontSize(18)
          .margin({ right: 8 })
        
        TextInput({ 
          placeholder: '搜索配方名称...',
          text: $$this.searchText 
        })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Color.Transparent)
          .border({ width: 0 })
          .onChange((value: string) => {
            console.info(`[SearchPage] TextInput onChange - value: "${value}"`);
            this.searchText = value;
            this.performSearch();
          })
          .onSubmit(() => {
            console.info(`[SearchPage] TextInput onSubmit - searchText: "${this.searchText}"`);
            // 立即执行搜索,不等待防抖
            if (this.debounceTimer !== -1) {
              clearTimeout(this.debounceTimer);
              this.debounceTimer = -1;
            }
            this.fetchRecipes(true);
          })
        
        // 清除按钮
        if (this.searchText.length > 0) {
          Button() {
            Text('✕')
              .fontSize(18)
              .fontColor('#999999')
          }
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .width(32)
          .height(32)
          .onClick(() => {
            this.searchText = '';
            this.recipes = [];
            this.hasError = false;
          })
        }
      }
      .layoutWeight(1)
      .height(44)
      .backgroundColor('#F5F5F5')
      .borderRadius(22)
      .padding({ left: 12, right: 4 })
      .margin({ right: 12 })
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 8 })
    .backgroundColor(Color.White)
    .shadow({
      radius: 4,
      color: '#00000008',
      offsetX: 0,
      offsetY: 2
    })
  }
  
  /**
   * 构建空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      Text('🔍')
        .fontSize(64)
        .opacity(0.3)
      
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
        Text('• 实时显示结果')
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
        .fontColor('#999999')
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
      Text('⚠️')
        .fontSize(64)
        .opacity(0.3)
      
      Text(this.errorMessage || '搜索失败')
        .fontSize(14)
        .fontColor('#FF3B30')
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .padding({ left: 20, right: 20 })
      
      // 提示信息卡片
      Column({ space: 8 }) {
        Text('💡 提示')
          .fontSize(12)
          .fontColor('#666666')
          .fontWeight(FontWeight.Bold)
        
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
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(() => {
            console.info('[SearchPage] User clicked retry button');
            this.fetchRecipes(true);
          })
        
        Button('测试连接')
          .fontSize(14)
          .backgroundColor('#52C41A')
          .borderRadius(20)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(async () => {
            console.info('[SearchPage] User clicked test connection button');
            await this.testAPIConnection();
            promptAction.showToast({ 
              message: '请查看控制台日志',
              duration: 2000
            });
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
      Text('📭')
        .fontSize(64)
        .opacity(0.3)
      
      Text(`未找到"${this.searchText}"相关的配方`)
        .fontSize(16)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
      
      Text('试试其他关键词吧')
        .fontSize(14)
        .fontColor('#CCCCCC')
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
          .fontColor('#666666')
        
        if (this.currentPage < this.totalPages) {
          Text(` (第 ${this.currentPage}/${this.totalPages} 页)`)
            .fontSize(12)
            .fontColor('#999999')
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
                .fontColor('#999999')
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
              .fontColor('#CCCCCC')
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
          .fontColor('#1A1A1A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Row({ space: 12 }) {
          Text(`👤 ${recipe.createdBy}`)
            .fontSize(13)
            .fontColor('#666666')
          
          Text('|')
            .fontSize(13)
            .fontColor('#DDDDDD')
          
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
        .color('#F0F0F0')
      
      // 底部信息
      Row() {
        // 原料信息
        if (recipe.ingredients && typeof recipe.ingredients === 'string') {
          Text(`🧪 ${recipe.ingredients.split(',').length} 种原料`)
            .fontSize(12)
            .fontColor('#999999')
        }
        
        Blank()
        
        // 互动信息
        Row({ space: 16 }) {
          Row({ space: 4 }) {
            Text('❤️')
              .fontSize(14)
            Text(recipe.likeCount.toString())
              .fontSize(12)
              .fontColor('#999999')
          }
          
          Row({ space: 4 }) {
            Text('⭐')
              .fontSize(14)
            Text(recipe.favoriteCount.toString())
              .fontSize(12)
              .fontColor('#999999')
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#00000010',
      offsetX: 0,
      offsetY: 2
    })
  }
}
