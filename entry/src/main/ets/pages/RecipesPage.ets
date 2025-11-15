// RecipesPage.ets - 配方列表页面

import { apiService } from '../services/APIService';
import { Recipe, RecipesResponse, Ingredient } from '../models/Recipe';
import { router } from '@kit.ArkUI';

@Component
export struct RecipesPage {
  @State recipes: Array<Recipe> = [];
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State errorMessage: string = '';
  
  private pageSize: number = 100; // 每次加载100条
  private sortType: string = 'default'; // default, likes, favorites, name

  aboutToAppear() {
    // 页面加载时获取第一页数据
    if (this.recipes.length === 0) {
      this.fetchRecipes(true);
    }
  }

  /**
   * 获取配方列表
   * @param reset 是否重置列表(刷新)
   */
  private async fetchRecipes(reset: boolean) {
    if (this.isLoading) {
      return;
    }
    
    if (reset) {
      this.currentPage = 1;
      this.totalPages = 1;
      this.recipes = [];
    }
    
    this.isLoading = true;
    this.errorMessage = '';
    
    try {
      const result: object = await apiService.fetchRecipes(
        this.currentPage,
        this.pageSize,
        '', // 搜索参数暂时为空
        this.sortType
      );
      
      const response: RecipesResponse = result as RecipesResponse;
      const newRecipes: Array<Recipe> = response.recipes || [];
      
      if (reset) {
        this.recipes = newRecipes;
      } else {
        // 追加新数据
        this.recipes = this.recipes.concat(newRecipes);
      }
      
      this.currentPage = response.currentPage + 1;
      this.totalPages = response.totalPages;
      
    } catch (error) {
      console.error('[RecipesPage] 获取配方失败:', error);
      this.errorMessage = '加载失败,请稍后重试';
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载更多
   */
  private loadMore() {
    if (this.currentPage <= this.totalPages && !this.isLoading) {
      this.fetchRecipes(false);
    }
  }

  /**
   * 刷新列表
   */
  private refresh() {
    this.fetchRecipes(true);
  }

  /**
   * 打开配方详情(路由跳转)
   */
  private openRecipeDetail(recipeId: string) {
    console.info(`[RecipesPage] openRecipeDetail - recipeId: ${recipeId}`);
    router.pushUrl({
      url: 'pages/RecipeDetailPage',
      params: {
        recipeId: recipeId
      }
    }).then(() => {
      console.info(`[RecipesPage] navigated to RecipeDetailPage`);
    }).catch((err: Error) => {
      console.error(`[RecipesPage] navigation failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('配方')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.White)
      
      // 内容区域
      if (this.recipes.length === 0 && !this.isLoading) {
        // 空状态
        Column() {
          Text('🍸')
            .fontSize(64)
            .opacity(0.3)
          
          Text('暂无配方')
            .fontSize(18)
            .fontColor('#999999')
            .margin({ top: 16 })
          
          Text(this.errorMessage || '可能是在加载中或连接失败')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
          
          Button('重新加载')
            .fontSize(14)
            .margin({ top: 20 })
            .onClick(() => {
              this.refresh();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F5F5')
      } else {
        // 配方网格列表
        Refresh({ refreshing: $$this.isLoading }) {
          List({ space: 12 }) {
            // 使用Grid布局在List中实现卡片网格
            ListItem() {
              GridRow({ columns: 2, gutter: { x: 12, y: 12 } }) {
                ForEach(this.recipes, (recipe: Recipe) => {
                  GridCol() {
                    RecipeCard({
                      recipe: recipe,
                      onTap: () => {
                        this.openRecipeDetail(recipe.id);
                      }
                    })
                  }
                }, (recipe: Recipe) => recipe.id)
              }
              .padding({ left: 12, right: 12, top: 12 })
            }
            
            // 加载更多指示器
            if (this.currentPage <= this.totalPages || this.isLoading) {
              ListItem() {
                Row() {
                  if (this.isLoading) {
                    LoadingProgress()
                      .width(30)
                      .height(30)
                      .margin({ right: 8 })
                    Text('加载中...')
                      .fontSize(14)
                      .fontColor('#999999')
                  } else if (this.currentPage <= this.totalPages) {
                    Button('加载更多')
                      .fontSize(14)
                      .type(ButtonType.Normal)
                      .borderRadius(20)
                      .backgroundColor('#1890ff')
                      .onClick(() => {
                        this.loadMore();
                      })
                  }
                }
                .width('100%')
                .height(60)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(() => {
          this.refresh();
        })
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
  @Prop @Watch('onRecipeUpdate') recipe: Recipe;
  onTap?: () => void;
  
  @State likeCount: number = 0;
  @State favoriteCount: number = 0;
  @State isLiked: boolean = false;
  @State isFavorited: boolean = false;
  @State expanded: boolean = false;
  @State isLoadingDetail: boolean = false;
  @State ingredients: Array<Ingredient> = [];

  aboutToAppear() {
    this.syncRecipeState();
  }

  /**
   * 监听recipe变化,同步状态
   */
  onRecipeUpdate() {
    this.syncRecipeState();
  }

  /**
   * 同步配方状态
   */
  private syncRecipeState() {
    // 同步交互状态
    this.likeCount = this.recipe.likeCount || 0;
    this.favoriteCount = this.recipe.favoriteCount || 0;
    this.isLiked = this.recipe.isLiked || false;
    this.isFavorited = this.recipe.isFavorited || false;
    
    // 如果有配料字符串,解析为数组
    if (typeof this.recipe.ingredients === 'string' && this.recipe.ingredients.length > 0) {
      const ingredientNames: Array<string> = this.recipe.ingredients.split(',');
      this.ingredients = ingredientNames.map((name: string): Ingredient => {
        const ingredient: Ingredient = {
          name: name.trim(),
          volume: 0
        };
        return ingredient;
      });
    }
  }

  /**
   * 切换点赞状态
   */
  private async toggleLike() {
    // 乐观更新UI
    const originalLikeCount = this.likeCount;
    const originalIsLiked = this.isLiked;
    
    if (this.isLiked) {
      this.likeCount = Math.max(0, this.likeCount - 1);
      this.isLiked = false;
    } else {
      this.likeCount += 1;
      this.isLiked = true;
    }
    
    try {
      await apiService.toggleLike(this.recipe.id);
      console.info(`[RecipeCard] 点赞操作成功 id=${this.recipe.id}`);
    } catch (error) {
      // 失败时回滚
      console.error('[RecipeCard] 点赞操作失败:', error);
      this.likeCount = originalLikeCount;
      this.isLiked = originalIsLiked;
    }
  }

  /**
   * 切换收藏状态
   */
  private async toggleFavorite() {
    const originalFavoriteCount = this.favoriteCount;
    const originalIsFavorited = this.isFavorited;
    
    if (this.isFavorited) {
      this.favoriteCount = Math.max(0, this.favoriteCount - 1);
      this.isFavorited = false;
    } else {
      this.favoriteCount += 1;
      this.isFavorited = true;
    }
    
    try {
      await apiService.toggleFavorite(this.recipe.id);
      console.info(`[RecipeCard] 收藏操作成功 id=${this.recipe.id}`);
    } catch (error) {
      console.error('[RecipeCard] 收藏操作失败:', error);
      this.favoriteCount = originalFavoriteCount;
      this.isFavorited = originalIsFavorited;
    }
  }

  /**
   * 切换展开配料
   */
  private async toggleExpanded() {
    this.expanded = !this.expanded;
    
    // 如果展开且没有详细配料信息,则加载详情
    if (this.expanded && this.ingredients.length === 0) {
      this.isLoadingDetail = true;
      try {
        const detail: object = await apiService.fetchRecipeDetail(this.recipe.id);
        const ingredientsData = Reflect.get(detail, 'ingredients') as Array<Ingredient>;
        if (ingredientsData && Array.isArray(ingredientsData)) {
          this.ingredients = ingredientsData;
        }
      } catch (error) {
        console.error('[RecipeCard] 加载配方详情失败:', error);
      } finally {
        this.isLoadingDetail = false;
      }
    }
  }

  build() {
    Column() {
      // 标题与作者
      Column({ space: 6 }) {
        Text(this.recipe.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(`创建者: ${this.recipe.createdBy}`)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ABV标签
      Row() {
        Text(`${this.recipe.estimatedAbv.toFixed(1)}% ABV`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1890ff')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('#E6F7FF')
          .borderRadius(6)
      }
      .width('100%')
      .margin({ top: 8 })

      // 预览配料按钮
      Row() {
        Blank()
        if (this.isLoadingDetail) {
          LoadingProgress()
            .width(20)
            .height(20)
        } else {
          Button(this.expanded ? '收起配料' : '预览配料')
            .fontSize(12)
            .height(28)
            .type(ButtonType.Normal)
            .borderRadius(14)
            .backgroundColor('#F0F0F0')
            .fontColor('#666666')
            .onClick(() => {
              this.toggleExpanded();
            })
        }
      }
      .width('100%')
      .margin({ top: 8 })

      // 配料列表(展开时显示)
      if (this.expanded && this.ingredients.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.ingredients, (ingredient: Ingredient) => {
            Row() {
              Text(ingredient.name)
                .fontSize(13)
                .fontColor('#333333')
                .layoutWeight(1)
              
              if (ingredient.volume > 0) {
                Text(`${ingredient.volume.toFixed(0)} ml`)
                  .fontSize(12)
                  .fontColor('#999999')
              }
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }, (ingredient: Ingredient, index: number) => `${this.recipe.id}_ing_${index}`)
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#FAFAFA')
        .borderRadius(8)
        .margin({ top: 8 })
      }

      // 点赞和收藏按钮
      Row() {
        // 点赞
        Row({ space: 6 }) {
          Text(this.isLiked ? '❤️' : '🤍')
            .fontSize(20)
          
          Text(`${this.likeCount}`)
            .fontSize(12)
            .fontColor('#999999')
        }
        .onClick(() => {
          this.toggleLike();
        })

        Blank()

        // 收藏
        Row({ space: 6 }) {
          Text(this.isFavorited ? '⭐' : '☆')
            .fontSize(20)
            .fontColor(this.isFavorited ? '#FFD700' : '#999999')
          
          if (this.favoriteCount > 0) {
            Text(`${this.favoriteCount}`)
              .fontSize(12)
              .fontColor('#999999')
          }
        }
        .onClick(() => {
          this.toggleFavorite();
        })
      }
      .width('100%')
      .margin({ top: 10 })
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
      console.info(`[RecipeCard] onClick - recipe id: ${this.recipe.id}`);
      if (this.onTap) {
        this.onTap();
      } else {
        console.warn('[RecipeCard] onTap callback is not defined');
      }
    })
  }
}
