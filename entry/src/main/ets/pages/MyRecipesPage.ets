// MyRecipesPage.ets - 我的配方页面
// 参考 Swift 项目中的 MyRecipesFullScreen

import { router } from '@kit.ArkUI';
import APIService from '../services/APIService';
import { Recipe } from '../models/Recipe';
import promptAction from '@ohos.promptAction';

@Entry
@Component
export struct MyRecipesPage {
  @State recipes: Array<Recipe> = [];
  @State isLoading: boolean = false;
  @State hasError: boolean = false;
  @State errorMessage: string = '';
  @State totalLikes: number = 0;
  
  aboutToAppear() {
    this.loadMyRecipes();
  }
  
  /**
   * 加载我的配方
   */
  private async loadMyRecipes() {
    this.isLoading = true;
    this.hasError = false;
    this.errorMessage = '';
    
    try {
      console.info('[MyRecipesPage] Loading my recipes...');
      const apiService = APIService.getInstance();
      const data = await apiService.fetchUserCreatedRecipes();
      
      if (Array.isArray(data)) {
        console.info(`[MyRecipesPage] 收到数据数组, 长度: ${data.length}`);
        if (data.length > 0) {
          console.info(`[MyRecipesPage] 第一条数据样例:`, JSON.stringify(data[0]));
        }
        
        // 先创建基础配方数据
        this.recipes = data.map((item: ESObject): Recipe => {
          return {
            id: (item['id'] || '') as string,
            name: (item['name'] || '未命名') as string,
            createdBy: (item['createdBy'] || item['created_by'] || '未知') as string,
            instructions: (item['instructions'] || '') as string,
            estimatedAbv: this.parseNumber(item['estimatedAbv'] || item['estimated_abv']),
            likeCount: this.parseNumber(item['likeCount'] || item['like_count']),
            favoriteCount: this.parseNumber(item['favoriteCount'] || item['favorite_count']),
            ingredients: (item['ingredients'] || '') as string
          };
        });
        
        console.info(`[MyRecipesPage] 成功解析 ${this.recipes.length} 个配方`);
        
        // 如果数据缺少统计信息,批量补充
        await this.enrichRecipesWithStats();
        
        // 计算总点赞数
        this.totalLikes = this.recipes.reduce((sum: number, recipe: Recipe) => {
          return sum + recipe.likeCount;
        }, 0);
        
        console.info(`[MyRecipesPage] 统计完成 - 总点赞: ${this.totalLikes}`);
      } else {
        console.warn('[MyRecipesPage] 数据不是数组格式');
        this.recipes = [];
        this.totalLikes = 0;
      }
    } catch (error) {
      console.error('[MyRecipesPage] Load failed:', error);
      this.hasError = true;
      this.errorMessage = error instanceof Error ? error.message : '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 补充配方的统计信息(点赞数和收藏数)
   */
  private async enrichRecipesWithStats() {
    // 检查是否需要补充统计信息
    const needsEnrichment = this.recipes.some(r => r.likeCount === 0 && r.favoriteCount === 0);
    if (!needsEnrichment || this.recipes.length === 0) {
      console.info('[MyRecipesPage] 无需补充统计信息');
      return;
    }
    
    console.info('[MyRecipesPage] 开始补充统计信息...');
    const apiService = APIService.getInstance();
    
    // 批量获取配方详情
    const promises = this.recipes.map(async (recipe: Recipe, index: number) => {
      try {
        const detail = await apiService.fetchRecipeDetail(recipe.id);
        if (detail) {
          // 更新统计信息
          this.recipes[index].likeCount = this.parseNumber(detail['likeCount'] || detail['like_count']);
          this.recipes[index].favoriteCount = this.parseNumber(detail['favoriteCount'] || detail['favorite_count']);
        }
      } catch (error) {
        console.warn(`[MyRecipesPage] 获取配方 ${recipe.id} 统计信息失败:`, error);
      }
    });
    
    await Promise.all(promises);
    console.info('[MyRecipesPage] 统计信息补充完成');
  }
  
  /**
   * 安全地解析数值
   */
  private parseNumber(value: ESObject): number {
    if (value === null || value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value as string);
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
      url: '@bundle:com.example.cybar/entry/ets/pages/RecipeDetailPage',
      params: {
        recipeId: recipe.id
      }
    }).catch((error: Error) => {
      console.error('[MyRecipesPage] Navigation failed:', error);
      promptAction.showToast({ message: '跳转失败' });
    });
  }
  
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button() {
          Row({ space: 4 }) {
            Text('←')
              .fontSize(24)
              .fontColor('#007DFF')
            Text('返回')
              .fontSize(16)
              .fontColor('#007DFF')
          }
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .height(44)
        .padding({ left: 4, right: 12 })
        .onClick(() => {
          router.back();
        })
        
        Text('我的配方')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        // 刷新按钮
        Button() {
          Text('🔄')
            .fontSize(20)
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .width(44)
        .height(44)
        .onClick(() => {
          this.loadMyRecipes();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor(Color.White)
      
      // 内容区域
      if (this.hasError) {
        this.buildErrorState();
      } else if (this.isLoading) {
        this.buildLoadingState();
      } else if (this.recipes.length === 0) {
        this.buildEmptyState();
      } else {
        this.buildRecipesList();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
  
  /**
   * 加载状态
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(50)
        .height(50)
        .color('#1890ff')
      
      Text('加载中...')
        .fontSize(14)
        .fontColor('#999999')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
  
  /**
   * 错误状态
   */
  @Builder
  buildErrorState() {
    Column({ space: 16 }) {
      Text('⚠️')
        .fontSize(64)
        .opacity(0.3)
      
      Text(this.errorMessage || '加载失败')
        .fontSize(16)
        .fontColor('#FF3B30')
        .textAlign(TextAlign.Center)
      
      Button('重试')
        .fontSize(14)
        .backgroundColor('#1890ff')
        .borderRadius(20)
        .padding({ left: 24, right: 24 })
        .margin({ top: 16 })
        .onClick(() => {
          this.loadMyRecipes();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      Text('📝')
        .fontSize(64)
        .opacity(0.3)
      
      Text('还没有创建配方')
        .fontSize(16)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
      
      Text('快去创建你的第一个鸡尾酒配方吧')
        .fontSize(14)
        .fontColor('#CCCCCC')
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })
      
      Button('刷新')
        .fontSize(14)
        .backgroundColor('#1890ff')
        .borderRadius(20)
        .padding({ left: 24, right: 24 })
        .margin({ top: 16 })
        .onClick(() => {
          this.loadMyRecipes();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 配方列表
   */
  @Builder
  buildRecipesList() {
    Scroll() {
      Column() {
        // 统计信息
        Row({ space: 16 }) {
          Text(`共 ${this.recipes.length} 个配方`)
            .fontSize(14)
            .fontColor('#666666')
          
          Text(`|`)
            .fontSize(14)
            .fontColor('#DDDDDD')
          
          Text(`总点赞 ${this.totalLikes}`)
            .fontSize(14)
            .fontColor('#FF3B30')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        
        // 配方网格
        GridRow({ columns: 2, gutter: 12 }) {
          ForEach(this.recipes, (recipe: Recipe) => {
            GridCol() {
              this.buildRecipeCard(recipe)
            }
          }, (recipe: Recipe) => recipe.id)
        }
        .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }
  
  /**
   * 配方卡片
   */
  @Builder
  buildRecipeCard(recipe: Recipe) {
    Column({ space: 12 }) {
      // 标题和创建者
      Column({ space: 6 }) {
        Text(recipe.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Text(`👤 ${recipe.createdBy}`)
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      
      // 酒精度
      Row() {
        Text(`${recipe.estimatedAbv.toFixed(1)}% ABV`)
          .fontSize(12)
          .fontColor('#1890ff')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      
      Divider()
        .color('#F0F0F0')
      
      // 互动信息
      Row() {
        Row({ space: 4 }) {
          Text('❤️')
            .fontSize(14)
          Text(recipe.likeCount.toString())
            .fontSize(11)
            .fontColor('#999999')
        }
        
        Blank()
        
        Row({ space: 4 }) {
          Text('⭐')
            .fontSize(14)
          Text(recipe.favoriteCount.toString())
            .fontSize(11)
            .fontColor('#999999')
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#00000010',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.navigateToDetail(recipe);
    })
  }
}
