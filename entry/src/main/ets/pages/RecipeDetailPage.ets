// RecipeDetailPage.ets - 配方详情页面(独立页面版本)
// 根据 server.js 重写,包含完整的配方详情功能
// 参考: server.js 中的 /api/recipes/:id, /api/recipes/:id/comments, 
//      /api/recipes/:id/like, /api/recipes/:id/favorite, /api/recipes/:id/interactions

import APIService from '../services/APIService';
import { Recipe, Ingredient } from '../models/Recipe';
import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';

/**
 * 评论接口
 * 对应 server.js 中 comment 表结构
 */
interface Comment {
  id: string;
  user_id: string;
  username: string;
  text: string;
  timestamp: string;
}

/**
 * 路由参数接口
 */
interface RouterParams {
  recipeId: string;
}

/**
 * 交互状态接口
 * 对应 server.js 中 /api/recipes/:id/interactions 返回结构
 */
interface InteractionStatus {
  likeCount: number;
  favoriteCount: number;
  isLiked: boolean;
  isFavorited: boolean;
}

/**
 * 配方详情接口
 * 对应 server.js 中 /api/recipes/:id 返回结构
 */
interface RecipeDetail {
  id: string;
  name: string;
  createdBy: string;
  instructions: string;
  estimatedAbv: number;
  likeCount: number;
  favoriteCount: number;
  ingredients: Array<Ingredient>;
}

@Entry
@Component
struct RecipeDetailPage {
  @State recipeId: string = '';
  private scroller: Scroller = new Scroller();
  
  // 配方数据
  @State recipe?: RecipeDetail = undefined;
  @State ingredients: Array<Ingredient> = [];
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  
  // 交互状态 (对应 server.js 中的 likes 和 favorites 表)
  @State likeCount: number = 0;
  @State favoriteCount: number = 0;
  @State isLiked: boolean = false;
  @State isFavorited: boolean = false;
  @State isLoadingInteraction: boolean = false;
  
  // 评论相关 (对应 server.js 中的 comment 表)
  @State comments: Array<Comment> = [];
  @State showComments: boolean = false;
  @State isLoadingComments: boolean = false;
  @State newCommentText: string = '';
  @State isSubmittingComment: boolean = false;
  @State commentError: string = '';
  
  // 登录状态
  @State isLoggedIn: boolean = false;

  aboutToAppear() {
    // 从路由参数获取 recipeId
    const params = router.getParams() as RouterParams;
    if (params && params.recipeId) {
      this.recipeId = params.recipeId;
      console.info(`[RecipeDetailPage] aboutToAppear - recipeId from router: ${this.recipeId}`);
      
      // 检查登录状态
      this.isLoggedIn = APIService.getInstance().isLoggedIn;
      
      // 加载配方详情
      this.loadRecipeDetail();
    } else {
      console.error('[RecipeDetailPage] recipeId not found in router params');
      this.errorMessage = '配方ID不能为空';
      this.isLoading = false;
    }
  }
  
  /**
   * 返回上一页
   */
  private goBack() {
    router.back();
  }

  /**
   * 安全地解析数值,处理各种可能的输入类型
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
    // 对于对象类型(如Decimal),尝试转换为字符串再解析
    const parsed = parseFloat(String(value));
    return isNaN(parsed) ? 0 : parsed;
  }

  /**
   * 加载配方详情
   * 对应 server.js: GET /api/recipes/:id
   * 返回: { id, name, instructions, estimatedAbv, createdBy, likeCount, favoriteCount, ingredients[] }
   */
  private async loadRecipeDetail() {
    console.info(`[RecipeDetailPage] loadRecipeDetail start - recipeId: ${this.recipeId}`);
    
    if (!this.recipeId) {
      this.errorMessage = '配方ID不能为空';
      this.isLoading = false;
      return;
    }
    
    this.isLoading = true;
    this.errorMessage = '';
    
    try {
      console.info(`[RecipeDetailPage] fetching recipe detail for id: ${this.recipeId}`);
      const detail: object = await APIService.getInstance().fetchRecipeDetail(this.recipeId);
      console.info(`[RecipeDetailPage] recipe detail fetched successfully`);
      
      // 解析配方数据
      const estimatedAbvValue = Reflect.get(detail, 'estimatedAbv') as string | number | object | null;
      const likeCountValue = Reflect.get(detail, 'likeCount') as string | number | object | null;
      const favoriteCountValue = Reflect.get(detail, 'favoriteCount') as string | number | object | null;
      
      console.info(`[RecipeDetailPage] Parsing values - estimatedAbv type: ${typeof estimatedAbvValue}, value: ${estimatedAbvValue}`);
      console.info(`[RecipeDetailPage] likeCount type: ${typeof likeCountValue}, value: ${likeCountValue}`);
      console.info(`[RecipeDetailPage] favoriteCount type: ${typeof favoriteCountValue}, value: ${favoriteCountValue}`);
      
      this.recipe = {
        id: Reflect.get(detail, 'id') as string,
        name: Reflect.get(detail, 'name') as string,
        createdBy: Reflect.get(detail, 'createdBy') as string,
        instructions: Reflect.get(detail, 'instructions') as string,
        estimatedAbv: this.parseNumber(estimatedAbvValue),
        likeCount: this.parseNumber(likeCountValue),
        favoriteCount: this.parseNumber(favoriteCountValue),
        ingredients: []
      };
      
      console.info(`[RecipeDetailPage] Parsed recipe - estimatedAbv: ${this.recipe.estimatedAbv}, likeCount: ${this.recipe.likeCount}`);
      
      // 解析原料列表
      const ingredientsData = Reflect.get(detail, 'ingredients') as Array<object>;
      if (ingredientsData && Array.isArray(ingredientsData)) {
        this.ingredients = ingredientsData.map((ing: object): Ingredient => {
          const volumeValue = Reflect.get(ing, 'volume') as string | number | object | null;
          const abvValue = Reflect.get(ing, 'abv') as string | number | object | null;
          
          const ingredient: Ingredient = {
            id: Reflect.get(ing, 'id') as string,
            cocktail_id: Reflect.get(ing, 'cocktail_id') as string,
            name: Reflect.get(ing, 'name') as string,
            volume: this.parseNumber(volumeValue),
            abv: this.parseNumber(abvValue)
          };
          return ingredient;
        });
        this.recipe.ingredients = this.ingredients;
      }
      
      // 初始化交互计数
      this.likeCount = this.recipe.likeCount || 0;
      this.favoriteCount = this.recipe.favoriteCount || 0;
      
      this.isLoading = false;
      console.info(`[RecipeDetailPage] recipe detail loaded, now loading interactions and comments`);
      
      // 异步加载交互状态和评论
      setTimeout(() => {
        if (this.isLoggedIn) {
          this.loadInteractionStatus();
        }
        this.loadComments();
      }, 100);
      
    } catch (error) {
      console.error('[RecipeDetailPage] 加载配方详情失败:', error);
      this.errorMessage = '加载失败,请稍后重试';
      this.isLoading = false;
    }
  }

  /**
   * 加载交互状态 (仅登录用户)
   * 对应 server.js: GET /api/recipes/:id/interactions
   * 返回: { likeCount, favoriteCount, isLiked, isFavorited }
   */
  private async loadInteractionStatus() {
    if (!this.isLoggedIn || !this.recipeId) {
      return;
    }

    this.isLoadingInteraction = true;
    
    try {
      const response: object = await APIService.getInstance().fetchRecipeInteractionStatus(this.recipeId);
      
      const likeCountValue = Reflect.get(response, 'likeCount') as string | number | object | null;
      const favoriteCountValue = Reflect.get(response, 'favoriteCount') as string | number | object | null;
      const isLikedValue = Reflect.get(response, 'isLiked') as boolean | string | number | null;
      const isFavoritedValue = Reflect.get(response, 'isFavorited') as boolean | string | number | null;
      
      this.likeCount = this.parseNumber(likeCountValue);
      this.favoriteCount = this.parseNumber(favoriteCountValue);
      this.isLiked = Boolean(isLikedValue);
      this.isFavorited = Boolean(isFavoritedValue);
      
      console.info(`[RecipeDetailPage] 交互状态加载成功 - like: ${this.isLiked}, favorite: ${this.isFavorited}`);
    } catch (error) {
      console.error('[RecipeDetailPage] 加载交互状态失败:', error);
    } finally {
      this.isLoadingInteraction = false;
    }
  }

  /**
   * 加载评论列表
   * 对应 server.js: GET /api/recipes/:id/comments
   * 返回: Array<{ id, user_id, username, text, timestamp }>
   */
  private async loadComments() {
    console.info(`[RecipeDetailPage] loadComments start - recipeId: ${this.recipeId}`);
    this.isLoadingComments = true;
    this.commentError = '';
    
    try {
      const result: Array<object> = await APIService.getInstance().fetchComments(this.recipeId);
      if (Array.isArray(result)) {
        this.comments = result.map((comment: object): Comment => {
          const commentItem: Comment = {
            id: Reflect.get(comment, 'id') as string,
            user_id: Reflect.get(comment, 'user_id') as string,
            username: Reflect.get(comment, 'username') as string,
            text: Reflect.get(comment, 'text') as string,
            timestamp: this.formatTimestamp(Reflect.get(comment, 'timestamp') as string)
          };
          return commentItem;
        });
        console.info(`[RecipeDetailPage] loaded ${this.comments.length} comments`);
      }
    } catch (error) {
      console.error('[RecipeDetailPage] 加载评论失败:', error);
      this.commentError = '加载评论失败';
    } finally {
      this.isLoadingComments = false;
    }
  }

  /**
   * 提交评论
   * 对应 server.js: POST /api/recipes/:id/comments
   * 请求: { commentText: string }
   * 返回: 新评论对象
   */
  private async submitComment() {
    // 验证评论内容
    if (!this.newCommentText || this.newCommentText.trim().length === 0) {
      this.commentError = '评论内容不能为空';
      return;
    }
    
    // 检查登录状态
    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录后再发表评论' });
      return;
    }
    
    this.isSubmittingComment = true;
    this.commentError = '';
    
    try {
      const newComment: object = await APIService.getInstance().addComment(
        this.recipeId, 
        this.newCommentText.trim()
      );
      
      // 添加新评论到列表头部
      const comment: Comment = {
        id: Reflect.get(newComment, 'id') as string,
        user_id: Reflect.get(newComment, 'user_id') as string,
        username: Reflect.get(newComment, 'username') as string,
        text: Reflect.get(newComment, 'text') as string,
        timestamp: this.formatTimestamp(Reflect.get(newComment, 'timestamp') as string)
      };
      this.comments.unshift(comment);
      
      // 清空输入框
      this.newCommentText = '';
      
      promptAction.showToast({ message: '评论发表成功' });
      console.info('[RecipeDetailPage] 评论提交成功');
    } catch (error) {
      console.error('[RecipeDetailPage] 提交评论失败:', error);
      this.commentError = '提交评论失败,请稍后重试';
      promptAction.showToast({ message: '提交评论失败' });
    } finally {
      this.isSubmittingComment = false;
    }
  }

  /**
   * 格式化时间戳
   */
  private formatTimestamp(timestamp: string): string {
    try {
      const date = new Date(timestamp);
      const now = new Date();
      const diff = now.getTime() - date.getTime();
      
      // 小于1分钟
      if (diff < 60000) {
        return '刚刚';
      }
      
      // 小于1小时
      if (diff < 3600000) {
        const minutes = Math.floor(diff / 60000);
        return `${minutes}分钟前`;
      }
      
      // 小于1天
      if (diff < 86400000) {
        const hours = Math.floor(diff / 3600000);
        return `${hours}小时前`;
      }
      
      // 小于7天
      if (diff < 604800000) {
        const days = Math.floor(diff / 86400000);
        return `${days}天前`;
      }
      
      // 返回完整日期
      const year = date.getFullYear();
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      const hour = date.getHours().toString().padStart(2, '0');
      const minute = date.getMinutes().toString().padStart(2, '0');
      
      return `${year}-${month}-${day} ${hour}:${minute}`;
    } catch (error) {
      return timestamp;
    }
  }

  /**
   * 切换点赞状态
   * 对应 server.js: POST /api/recipes/:id/like
   * 返回: { success, isLiked, likeCount, favoriteCount }
   */
  private async toggleLike() {
    // 检查登录状态
    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录后再点赞' });
      return;
    }
    
    // 保存原始状态以便回滚
    const originalLikeCount: number = this.likeCount;
    const originalIsLiked: boolean = this.isLiked;
    
    // 乐观更新UI
    if (this.isLiked) {
      this.likeCount = Math.max(0, this.likeCount - 1);
      this.isLiked = false;
    } else {
      this.likeCount += 1;
      this.isLiked = true;
    }
    
    try {
      const response: object = await APIService.getInstance().toggleLike(this.recipeId);
      
      // 从服务器响应更新状态
      const success = Reflect.get(response, 'success') as boolean;
      if (success) {
        const isLikedValue = Reflect.get(response, 'isLiked') as boolean | string | number | null;
        const likeCountValue = Reflect.get(response, 'likeCount') as string | number | object | null;
        const favoriteCountValue = Reflect.get(response, 'favoriteCount') as string | number | object | null;
        
        this.isLiked = Boolean(isLikedValue);
        this.likeCount = this.parseNumber(likeCountValue);
        
        // 同时更新收藏数(服务器一并返回)
        if (favoriteCountValue !== undefined && favoriteCountValue !== null) {
          this.favoriteCount = this.parseNumber(favoriteCountValue);
        }
      }
      
      console.info(`[RecipeDetailPage] 点赞成功 id=${this.recipeId}, isLiked=${this.isLiked}`);
    } catch (error) {
      console.error('[RecipeDetailPage] 点赞失败:', error);
      // 回滚状态
      this.likeCount = originalLikeCount;
      this.isLiked = originalIsLiked;
      promptAction.showToast({ message: '操作失败,请稍后重试' });
    }
  }

  /**
   * 切换收藏状态
   * 对应 server.js: POST /api/recipes/:id/favorite
   * 返回: { success, isFavorited, likeCount, favoriteCount }
   */
  private async toggleFavorite() {
    // 检查登录状态
    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录后再收藏' });
      return;
    }
    
    // 保存原始状态以便回滚
    const originalFavoriteCount: number = this.favoriteCount;
    const originalIsFavorited: boolean = this.isFavorited;
    
    // 乐观更新UI
    if (this.isFavorited) {
      this.favoriteCount = Math.max(0, this.favoriteCount - 1);
      this.isFavorited = false;
    } else {
      this.favoriteCount += 1;
      this.isFavorited = true;
    }
    
    try {
      const response: object = await APIService.getInstance().toggleFavorite(this.recipeId);
      
      // 从服务器响应更新状态
      const success = Reflect.get(response, 'success') as boolean;
      if (success) {
        const isFavoritedValue = Reflect.get(response, 'isFavorited') as boolean | string | number | null;
        const favoriteCountValue = Reflect.get(response, 'favoriteCount') as string | number | object | null;
        const likeCountValue = Reflect.get(response, 'likeCount') as string | number | object | null;
        
        this.isFavorited = Boolean(isFavoritedValue);
        this.favoriteCount = this.parseNumber(favoriteCountValue);
        
        // 同时更新点赞数(服务器一并返回)
        if (likeCountValue !== undefined && likeCountValue !== null) {
          this.likeCount = this.parseNumber(likeCountValue);
        }
      }
      
      console.info(`[RecipeDetailPage] 收藏成功 id=${this.recipeId}, isFavorited=${this.isFavorited}`);
    } catch (error) {
      console.error('[RecipeDetailPage] 收藏失败:', error);
      // 回滚状态
      this.favoriteCount = originalFavoriteCount;
      this.isFavorited = originalIsFavorited;
      promptAction.showToast({ message: '操作失败,请稍后重试' });
    }
  }

  /**
   * 计算总容量
   */
  private calculateTotalVolume(): number {
    let total = 0;
    for (let i = 0; i < this.ingredients.length; i++) {
      const ing: Ingredient = this.ingredients[i];
      if (ing.volume) {
        total += ing.volume;
      }
    }
    return total;
  }

  build() {
    Column() {
      // 顶部导航栏
      this.buildTopBar()
      
      if (this.isLoading) {
        // 加载状态
        Column() {
          LoadingProgress()
            .width(50)
            .height(50)
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMessage) {
        // 错误状态
        Column() {
          Text('⚠️')
            .fontSize(64)
            .opacity(0.3)
          
          Text(this.errorMessage)
            .fontSize(16)
            .fontColor('#999999')
            .margin({ top: 16 })
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
          
          Button('重新加载')
            .fontSize(14)
            .margin({ top: 20 })
            .onClick(() => {
              this.loadRecipeDetail();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.recipe) {
        // 内容展示
        Scroll() {
          Column({ space: 16 }) {
            // 标题和作者信息
            this.buildHeaderSection()
            
            // 操作按钮行
            this.buildActionButtons()
            
            // 配料清单
            this.buildIngredientsSection()
            
            // 调制说明
            this.buildInstructionsSection()
            
            // 营养信息
            this.buildNutritionSection()
            
            // 评论区域
            this.buildCommentsSection()
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F5F5F5')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .bindSheet($$this.showComments, this.buildCommentsSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      dragBar: true,
      backgroundColor: Color.White,
      onDisappear: () => {
        this.showComments = false;
      }
    })
  }

  /**
   * 构建顶部导航栏
   */
  @Builder
  buildTopBar() {
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
        this.goBack();
      })
      
      Blank()
      
      Text('配方详情')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
      
      Blank()
      
      // 占位,保持标题居中
      Row()
        .width(80)
        .height(44)
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 16 })
    .backgroundColor(Color.White)
    .shadow({
      radius: 4,
      color: '#00000008',
      offsetX: 0,
      offsetY: 2
    })
  }

  /**
   * 构建标题区域
   */
  @Builder
  buildHeaderSection() {
    if (this.recipe) {
      Column({ space: 12 }) {
        Text(this.recipe.name)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%')
        .lineHeight(38)
      
      Row({ space: 12 }) {
        Text(`👤 ${this.recipe.createdBy}`)
          .fontSize(15)
          .fontColor('#666666')
        
        Text('|')
          .fontSize(15)
          .fontColor('#DDDDDD')
        
        Text(`${this.recipe.estimatedAbv.toFixed(1)}% ABV`)
          .fontSize(15)
          .fontColor('#1890ff')
          .fontWeight(FontWeight.Medium)
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
    }
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      // 点赞按钮
      Button() {
        Row({ space: 8 }) {
          Text(this.isLiked ? '❤️' : '🤍')
            .fontSize(20)
          Text(`${this.likeCount}`)
            .fontSize(14)
            .fontColor(this.isLiked ? '#FF4D4F' : '#666666')
            .fontWeight(FontWeight.Medium)
        }
      }
      .type(ButtonType.Normal)
      .backgroundColor(this.isLiked ? '#FFE4E6' : '#F5F5F5')
      .borderRadius(20)
      .height(44)
      .layoutWeight(1)
      .onClick(() => {
        this.toggleLike();
      })

      // 收藏按钮
      Button() {
        Row({ space: 8 }) {
          Text(this.isFavorited ? '⭐' : '☆')
            .fontSize(20)
            .fontColor(this.isFavorited ? '#FFD700' : '#999999')
          Text(`${this.favoriteCount}`)
            .fontSize(14)
            .fontColor(this.isFavorited ? '#FFA500' : '#666666')
            .fontWeight(FontWeight.Medium)
        }
      }
      .type(ButtonType.Normal)
      .backgroundColor(this.isFavorited ? '#FFF8DC' : '#F5F5F5')
      .borderRadius(20)
      .height(44)
      .layoutWeight(1)
      .onClick(() => {
        this.toggleFavorite();
      })

      // 评论按钮
      Button() {
        Row({ space: 8 }) {
          Text('💬')
            .fontSize(20)
          Text(`${this.comments.length}`)
            .fontSize(14)
            .fontColor('#666666')
            .fontWeight(FontWeight.Medium)
        }
      }
      .type(ButtonType.Normal)
      .backgroundColor('#F5F5F5')
      .borderRadius(20)
      .height(44)
      .layoutWeight(1)
      .onClick(() => {
        this.showComments = true;
      })
    }
    .width('100%')
  }

  /**
   * 构建配料清单
   */
  @Builder
  buildIngredientsSection() {
    if (this.ingredients.length > 0) {
      Column({ space: 14 }) {
        Text('🧪 配料清单')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .width('100%')
        
        Column({ space: 0 }) {
          ForEach(this.ingredients, (ingredient: Ingredient, index: number) => {
            Column() {
              Row() {
                Column({ space: 4 }) {
                  Text(ingredient.name)
                    .fontSize(16)
                    .fontColor('#333333')
                    .fontWeight(FontWeight.Medium)
                  
                  if (ingredient.abv && ingredient.abv > 0) {
                    Text(`${ingredient.abv.toFixed(1)}% ABV`)
                      .fontSize(13)
                      .fontColor('#999999')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                
                Text(`${ingredient.volume.toFixed(0)} ml`)
                  .fontSize(16)
                  .fontColor('#1890ff')
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .padding(16)
              
              if (index < this.ingredients.length - 1) {
                Divider()
                  .color('#F0F0F0')
              }
            }
          }, (ingredient: Ingredient, index: number) => `${this.recipeId}_ing_${index}`)
        }
        .width('100%')
        .backgroundColor('#FAFAFA')
        .borderRadius(12)
        
        // 总计
        Row() {
          Text('总容量')
            .fontSize(15)
            .fontColor('#666666')
          
          Blank()
          
          Text(`${this.calculateTotalVolume().toFixed(0)} ml`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890ff')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#E6F7FF')
        .borderRadius(12)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
    }
  }

  /**
   * 构建调制说明
   */
  @Builder
  buildInstructionsSection() {
    if (this.recipe && this.recipe.instructions && this.recipe.instructions.length > 0) {
      Column({ space: 14 }) {
        Text('📝 调制步骤')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .width('100%')
        
        Text(this.recipe.instructions)
          .fontSize(15)
          .fontColor('#555555')
          .lineHeight(26)
          .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  /**
   * 构建营养信息
   */
  @Builder
  buildNutritionSection() {
    if (this.recipe) {
      Column({ space: 14 }) {
      Text('📊 营养信息')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%')
      
      Row({ space: 16 }) {
        Column({ space: 8 }) {
          Text('酒精度')
            .fontSize(13)
            .fontColor('#999999')
          Text(`${this.recipe.estimatedAbv.toFixed(1)}%`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890ff')
        }
        .layoutWeight(1)
        .padding(16)
        .backgroundColor('#E6F7FF')
        .borderRadius(12)
        
        Column({ space: 8 }) {
          Text('总容量')
            .fontSize(13)
            .fontColor('#999999')
          Text(`${this.calculateTotalVolume().toFixed(0)} ml`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#52C41A')
        }
        .layoutWeight(1)
        .padding(16)
        .backgroundColor('#F6FFED')
        .borderRadius(12)
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
    }
  }

  /**
   * 构建评论预览区域
   */
  @Builder
  buildCommentsSection() {
    Column({ space: 14 }) {
      Row() {
        Text(`💬 评论 (${this.comments.length})`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        
        Blank()
        
        if (this.comments.length > 0) {
          Button('查看全部')
            .fontSize(14)
            .type(ButtonType.Normal)
            .backgroundColor('#F0F0F0')
            .borderRadius(16)
            .height(32)
            .onClick(() => {
              this.showComments = true;
            })
        }
      }
      .width('100%')
      
      if (this.isLoadingComments) {
        Row() {
          LoadingProgress()
            .width(30)
            .height(30)
          Text('加载评论中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ left: 10 })
        }
        .width('100%')
        .height(60)
        .justifyContent(FlexAlign.Center)
      } else if (this.commentError) {
        Column({ space: 8 }) {
          Text('⚠️')
            .fontSize(32)
            .opacity(0.5)
          Text(this.commentError)
            .fontSize(14)
            .fontColor('#FF3B30')
          Button('重新加载')
            .fontSize(14)
            .height(32)
            .onClick(() => {
              this.loadComments();
            })
        }
        .width('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else if (this.comments.length === 0) {
        Column({ space: 12 }) {
          Text('📝')
            .fontSize(48)
            .opacity(0.3)
          Text('暂无评论')
            .fontSize(16)
            .fontColor('#666666')
            .fontWeight(FontWeight.Medium)
          Text(this.isLoggedIn ? '快来发表第一条评论吧!' : '登录后可以发表评论')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .padding(32)
        .justifyContent(FlexAlign.Center)
      } else {
        // 显示前3条评论
        Column({ space: 12 }) {
          ForEach(this.comments.slice(0, 3), (comment: Comment) => {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(comment.username)
                  .fontSize(14)
                  .fontColor('#333333')
                  .fontWeight(FontWeight.Medium)
                
                Blank()
                
                Text(comment.timestamp)
                  .fontSize(12)
                  .fontColor('#999999')
              }
              .width('100%')
              
              Text(comment.text)
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
                .width('100%')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FAFAFA')
            .borderRadius(8)
          }, (comment: Comment) => comment.id)
          
          // 如果评论超过3条,显示提示
          if (this.comments.length > 3) {
            Text(`还有 ${this.comments.length - 3} 条评论`)
              .fontSize(13)
              .fontColor('#007DFF')
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 4, bottom: 4 })
              .onClick(() => {
                this.showComments = true;
              })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }

  /**
   * 构建评论半模态
   */
  @Builder
  buildCommentsSheet() {
    Column() {
      // 标题栏
      Row() {
        Text(`评论 (${this.comments.length})`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        
        Blank()
        
        Button() {
          Text('✕')
            .fontSize(22)
            .fontColor('#666666')
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          this.showComments = false;
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 8 })
      .borderRadius({ topLeft: 16, topRight: 16 })
      
      Divider()
      
      // 评论列表
      if (this.isLoadingComments) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('加载评论中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.comments.length === 0) {
        Column({ space: 12 }) {
          Text('📝')
            .fontSize(64)
            .opacity(0.3)
          Text('暂无评论')
            .fontSize(16)
            .fontColor('#666666')
            .fontWeight(FontWeight.Medium)
          Text(this.isLoggedIn ? '快来发表第一条评论吧!' : '登录后可以发表评论')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.comments, (comment: Comment, index: number) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  // 用户头像占位符
                  Text(comment.username.substring(0, 1).toUpperCase())
                    .fontSize(16)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Bold)
                    .width(36)
                    .height(36)
                    .textAlign(TextAlign.Center)
                    .backgroundColor('#1890ff')
                    .borderRadius(18)
                  
                  Column({ space: 4 }) {
                    Text(comment.username)
                      .fontSize(15)
                      .fontColor('#333333')
                      .fontWeight(FontWeight.Medium)
                    
                    Text(comment.timestamp)
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                  .alignItems(HorizontalAlign.Start)
                  
                  Blank()
                  
                  // 楼层号
                  Text(`#${this.comments.length - index}`)
                    .fontSize(12)
                    .fontColor('#999999')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor('#F5F5F5')
                    .borderRadius(4)
                }
                .width('100%')
                
                Text(comment.text)
                  .fontSize(14)
                  .fontColor('#666666')
                  .lineHeight(22)
                  .width('100%')
                  .margin({ left: 44 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#F9F9F9')
              .borderRadius(12)
            }
          }, (comment: Comment) => comment.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .scrollBar(BarState.Auto)
      }
      
      Divider()
      
      // 评论输入区
      if (this.isLoggedIn) {
        Column({ space: 8 }) {
          // 错误提示
          if (this.commentError) {
            Row({ space: 8 }) {
              Text('⚠️')
                .fontSize(14)
              Text(this.commentError)
                .fontSize(13)
                .fontColor('#FF3B30')
            }
            .width('100%')
            .padding({ left: 4, right: 4 })
          }
          
          // 输入框
          Row({ space: 12 }) {
            TextInput({ placeholder: '写下你的评论...', text: $$this.newCommentText })
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(22)
              .padding({ left: 16, right: 16 })
              .maxLength(500)
            
            Button(this.isSubmittingComment ? '发送中' : '发送')
              .type(ButtonType.Normal)
              .backgroundColor(this.isSubmittingComment || this.newCommentText.trim().length === 0 ? '#CCCCCC' : '#1890ff')
              .fontColor(Color.White)
              .height(44)
              .borderRadius(22)
              .padding({ left: 20, right: 20 })
              .enabled(!this.isSubmittingComment && this.newCommentText.trim().length > 0)
              .onClick(() => {
                this.submitComment();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
      } else {
        // 未登录提示
        Row({ space: 12 }) {
          Text('请先登录后再发表评论')
            .fontSize(14)
            .fontColor('#666666')
            .layoutWeight(1)
          
          Button('去登录')
            .type(ButtonType.Normal)
            .backgroundColor('#1890ff')
            .fontColor(Color.White)
            .height(36)
            .onClick(() => {
              this.showComments = false;
              // TODO: 跳转到登录页面
              promptAction.showToast({ message: '请前往登录页面' });
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFAF0')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
