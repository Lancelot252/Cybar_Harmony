// RecommendationsPage.ets - 推荐页面
// 参考 Swift 项目中的 RecommendationsView 和 LOCAL_RECOMMENDATION_ALGORITHM.md

import { router } from '@kit.ArkUI';
import APIService from '../services/APIService';
import { Recipe, APIIngredient } from '../common/models/Recipe';
import promptAction from '@ohos.promptAction';

// 用户偏好模型
class UserPreferences {
  preferredAbv: number = 15.0;        // 偏好的酒精度
  abvWeight: number = 1.0;            // 酒精度权重
  popularityWeight: number = 0.1;     // 受欢迎程度权重
  randomWeight: number = 0.3;         // 随机因子权重
  favoriteCreators: string[] = [];    // 喜欢的创建者列表
  ingredientWeights: Map<string, number> = new Map(); // 原料偏好
  ingredientMatchWeight: number = 1.0; // 原料匹配权重
}

// 评分后的推荐项
interface ScoredRec {
  id: string;
  name: string;
  createdBy: string;
  estimatedAbv: number;
  matchPercentage: number;
  reasons: string[];
  likeCount: number;
  favoriteCount: number;
  ingredients: string;
  ingredientDetails?: APIIngredient[]; // 详细配料信息
}

// 评分中间结果
interface ScoredItem {
  recipe: Recipe;
  score: number;
  reasons: string[];
}

@Component
export struct RecommendationsPage {
  @State recs: Array<ScoredRec> = [];        // 当前展示的推荐(4个)
  @State top20: Array<ScoredRec> = [];       // Top20 推荐池
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;      // 下拉刷新状态
  @State hasError: boolean = false;
  @State errorMessage: string = '';
  
  aboutToAppear() {
    if (this.top20.length === 0) {
      this.loadRecommendations();
    } else {
      this.pickDisplayFour();
    }
  }
  
  /**
   * 加载推荐
   */
  private async loadRecommendations() {
    this.isLoading = true;
    this.hasError = false;
    this.errorMessage = '';
    
    try {
      console.info('[RecommendationsPage] 开始加载推荐...');
      const apiService = APIService.getInstance();
      
      // 1. 获取随机100个配方
      const randomRecipes = await apiService.fetchRandomRecipes(100);
      console.info(`[RecommendationsPage] 获取到 ${randomRecipes.length} 个随机配方`);
      
      if (!Array.isArray(randomRecipes) || randomRecipes.length === 0) {
        this.errorMessage = '暂无配方数据';
        this.hasError = true;
        return;
      }
      
      // 2. 构建用户偏好
      const prefs = await this.buildUserPreferences();
      
      // 3. 本地评分和排序
      const recipes = this.parseRecipes(randomRecipes);
      const scored = this.scoreAndSort(recipes, prefs);
      
      // 4. 取Top20
      this.top20 = scored.slice(0, Math.min(20, scored.length));
      console.info(`[RecommendationsPage] Top20 推荐生成完成`);
      
      // 5. 从Top20中随机选4个展示
      this.pickDisplayFour();
      
    } catch (error) {
      console.error('[RecommendationsPage] 加载推荐失败:', error);
      this.hasError = true;
      this.errorMessage = error instanceof Error ? error.message : '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 从Top20中随机选择4个展示
   */
  private pickDisplayFour() {
    if (this.top20.length === 0) {
      this.recs = [];
      return;
    }
    
    // 洗牌算法
    const pool = [...this.top20];
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      // ArkTS不支持解构赋值,使用临时变量
      const temp = pool[i];
      pool[i] = pool[j];
      pool[j] = temp;
    }
    
    this.recs = pool.slice(0, Math.min(4, pool.length));
    console.info(`[RecommendationsPage] 展示 ${this.recs.length} 个推荐`);
  }
  
  /**
   * 刷新推荐 - 下拉刷新时调用
   */
  private async refreshRecommendations() {
    console.info('[RecommendationsPage] 下拉刷新开始');
    this.isRefreshing = true;
    
    try {
      // 如果 top20 为空,则完整加载
      if (this.top20.length === 0) {
        await this.loadRecommendations();
      } else {
        // 否则从 top20 中重新抽取4个
        this.pickDisplayFour();
        
        // 手动延迟一下,让刷新动画正常显示
        await new Promise<void>((resolve) => {
          setTimeout(() => {
            resolve();
          }, 500);
        });
      }
    } finally {
      this.isRefreshing = false;
      console.info('[RecommendationsPage] 下拉刷新完成');
    }
  }
  
  /**
   * 构建用户偏好
   */
  private async buildUserPreferences(): Promise<UserPreferences> {
    const prefs = new UserPreferences();
    const apiService = APIService.getInstance();
    
    // 未登录:使用默认偏好
    if (!apiService.isLoggedIn) {
      console.info('[RecommendationsPage] 未登录,使用默认偏好');
      return prefs;
    }
    
    try {
      // 获取用户点赞和收藏
      const results = await Promise.all([
        apiService.fetchUserLikes().catch(() => []),
        apiService.fetchUserFavorites().catch(() => [])
      ]);
      const likesData = results[0];
      const favsData = results[1];
      
      const likes = this.parseRecipes(likesData);
      const favs = this.parseRecipes(favsData);
      const all = [...likes, ...favs];
      
      if (all.length > 0) {
        // 计算偏好ABV(平均值)
        const abvSum = all.reduce((sum, r) => sum + r.estimatedAbv, 0);
        prefs.preferredAbv = abvSum / all.length;
        
        // 统计喜欢的作者(Top 10)
        const creatorCount: Map<string, number> = new Map();
        all.forEach(r => {
          const count = creatorCount.get(r.createdBy) || 0;
          creatorCount.set(r.createdBy, count + 1);
        });
        prefs.favoriteCreators = Array.from(creatorCount.entries())
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)
          .map((entry) => entry[0]);
        
        // 统计原料偏好:收藏记2分,点赞记1分
        const ingWeights: Map<string, number> = new Map();
        likes.forEach(r => {
          this.extractIngredientNames(r.ingredients).forEach(name => {
            ingWeights.set(name, (ingWeights.get(name) || 0) + 1);
          });
        });
        favs.forEach(r => {
          this.extractIngredientNames(r.ingredients).forEach(name => {
            ingWeights.set(name, (ingWeights.get(name) || 0) + 2);
          });
        });
        prefs.ingredientWeights = ingWeights;
        
        console.info(`[RecommendationsPage] 用户偏好: ABV=${prefs.preferredAbv.toFixed(1)}, 原料=${ingWeights.size}种`);
      }
    } catch (error) {
      console.warn('[RecommendationsPage] 构建用户偏好失败:', error);
    }
    
    return prefs;
  }
  
  /**
   * 评分和排序
   */
  private scoreAndSort(recipes: Recipe[], prefs: UserPreferences): ScoredRec[] {
    const scored: Array<ScoredItem> = [];
    
    recipes.forEach(r => {
      // ABV评分: 10 - abs(recipe.abv - pref.abv)
      const abvScore = Math.max(0, 10 - Math.abs(r.estimatedAbv - prefs.preferredAbv));
      
      // 受欢迎程度
      const popularityScore = Math.max(0, r.likeCount);
      
      // 随机因子
      const randomScore = Math.floor(Math.random() * 6); // 0-5
      
      // 作者加分
      const creatorBonus = prefs.favoriteCreators.includes(r.createdBy) ? 15 : 0;
      
      // 原料匹配分
      let ingredientScore = 0;
      const matchedIngs: string[] = [];
      if (prefs.ingredientWeights.size > 0) {
        const recipeIngs = this.extractIngredientNames(r.ingredients);
        recipeIngs.forEach(ing => {
          if (prefs.ingredientWeights.has(ing)) {
            matchedIngs.push(ing);
          }
        });
        ingredientScore = Math.min(4, matchedIngs.length);
      }
      
      // 总分计算
      const score = abvScore * prefs.abvWeight +
                    popularityScore * prefs.popularityWeight +
                    randomScore * prefs.randomWeight +
                    creatorBonus +
                    ingredientScore * prefs.ingredientMatchWeight;
      
      // 生成推荐理由
      const reasons: string[] = [];
      if (matchedIngs.length > 0) {
        const top3 = matchedIngs.slice(0, 3).join('、');
        reasons.push(`包含常用原料:${top3}`);
      }
      if (abvScore > 6) {
        reasons.push('酒精度接近你的偏好');
      }
      if (creatorBonus > 0) {
        reasons.push(`你常看调酒师:${r.createdBy}`);
      }
      if (popularityScore > 20) {
        reasons.push('较受欢迎的配方');
      }
      if (reasons.length === 0) {
        reasons.push('为你探索新口味');
      }
      
      const item: ScoredItem = { recipe: r, score: score, reasons: reasons };
      scored.push(item);
    });
    
    // 排序并转换
    scored.sort((a, b) => b.score - a.score);
    const maxScore = scored.length > 0 ? scored[0].score : 1;
    
    return scored.map(item => {
      const pct = Math.min(100, Math.max(1, Math.round((item.score / maxScore) * 100)));
      const r = item.recipe;
      const ingredientsStr = this.extractIngredientNames(r.ingredients).join(', ');
      const result: ScoredRec = {
        id: r.id,
        name: r.name,
        createdBy: r.createdBy,
        estimatedAbv: r.estimatedAbv,
        matchPercentage: pct,
        reasons: item.reasons,
        likeCount: r.likeCount,
        favoriteCount: r.favoriteCount,
        ingredients: ingredientsStr,
        ingredientDetails: r.ingredients // 保留详细配料信息
      };
      return result;
    });
  }
  
  /**
   * 解析配方数据
   */
  private parseRecipes(data: Array<object>): Recipe[] {
    console.info(`[RecommendationsPage] 开始解析 ${data.length} 个配方`);
    
    return data.map((item: ESObject): Recipe => {
      // 处理 ingredients - 可能是数组或字符串
      let ingredients: APIIngredient[] | undefined = undefined;
      const rawIngredients: ESObject = item['ingredients'];
      if (rawIngredients && Array.isArray(rawIngredients)) {
        ingredients = rawIngredients as APIIngredient[];
        console.info(`[RecommendationsPage] 配方 ${item['name']} 有 ${ingredients.length} 个配料`);
      } else {
        console.info(`[RecommendationsPage] 配方 ${item['name']} 没有配料数组, rawIngredients type: ${typeof rawIngredients}`);
      }
      
      return {
        id: (item['id'] || '') as string,
        name: (item['name'] || '未命名') as string,
        createdBy: (item['createdBy'] || item['created_by'] || '未知') as string,
        instructions: (item['instructions'] || '') as string,
        estimatedAbv: this.parseNumber(item['estimatedAbv'] || item['estimated_abv']),
        likeCount: this.parseNumber(item['likeCount'] || item['like_count']),
        favoriteCount: this.parseNumber(item['favoriteCount'] || item['favorite_count']),
        ingredients: ingredients
      };
    });
  }
  
  /**
   * 从原料提取原料名称列表
   * 支持: APIIngredient[] | string | undefined
   */
  private extractIngredientNames(ingredients: APIIngredient[] | undefined): string[] {
    if (!ingredients) return [];
    
    // 使用 ESObject 来处理可能的字符串或数组类型
    const ingsObj: ESObject = ingredients as ESObject;
    
    // 如果是字符串,分割处理
    if (typeof ingsObj === 'string') {
      const strIngs = ingsObj as string;
      if (strIngs.length === 0) return [];
      const parts: string[] = strIngs.split(/[,，、]/);
      const trimmed: string[] = parts.map((s: string): string => s.trim().toLowerCase());
      const filtered: string[] = trimmed.filter((s: string): boolean => s.length > 0);
      const cleaned: string[] = filtered.map((s: string): string => s.replace(/\(.*?\)/g, '').trim());
      return cleaned;
    }
    
    // 如果是数组,从APIIngredient提取name
    if (Array.isArray(ingsObj)) {
      const arrIngs = ingsObj as APIIngredient[];
      if (arrIngs.length === 0) return [];
      const names: string[] = arrIngs.map((ing: APIIngredient): string => ing.name.trim().toLowerCase());
      const filtered: string[] = names.filter((s: string): boolean => s.length > 0);
      const cleaned: string[] = filtered.map((s: string): string => s.replace(/\(.*?\)/g, '').trim());
      return cleaned;
    }
    
    return [];
  }
  
  /**
   * 安全解析数值
   */
  private parseNumber(value: ESObject): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === 'number') return value;
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
  private navigateToDetail(rec: ScoredRec) {
    router.pushUrl({
      url: '@bundle:com.example.cybar/entry/ets/pages/RecipeDetailPage',
      params: {
        recipeId: rec.id
      }
    }).catch((error: Error) => {
      console.error('[RecommendationsPage] Navigation failed:', error);
      promptAction.showToast({ message: '跳转失败' });
    });
  }
  
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('推荐')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      
      // 内容区域
      if (this.hasError) {
        this.buildErrorState();
      } else if (this.isLoading) {
        this.buildLoadingState();
      } else if (this.recs.length === 0) {
        this.buildEmptyState();
      } else {
        this.buildRecommendationsList();
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
      
      Text('正在生成个性化推荐...')
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
          this.loadRecommendations();
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
      Text('✨')
        .fontSize(64)
        .opacity(0.3)
      
      Text('暂无推荐')
        .fontSize(16)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
      
      Text('去点赞/收藏一些配方试试')
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
          this.loadRecommendations();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }
  
  /**
   * 推荐列表
   */
  @Builder
  buildRecommendationsList() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.recs, (rec: ScoredRec) => {
            this.buildRecommendationCard(rec)
          }, (rec: ScoredRec) => rec.id)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing(async () => {
      await this.refreshRecommendations();
    })
  }
  
  /**
   * 推荐卡片 - 单行布局
   */
  @Builder
  buildRecommendationCard(rec: ScoredRec) {
    RecommendationCardComponent({ rec: rec })
  }
}

/**
 * 推荐卡片组件 - 独立状态管理
 */
@Component
struct RecommendationCardComponent {
  @Prop rec: ScoredRec;
  @State displayIngredients: APIIngredient[] = [];
  @State isFetchingDetails: boolean = false;
  
  aboutToAppear() {
    // 尝试使用已有的配料数据
    if (this.rec.ingredientDetails && this.rec.ingredientDetails.length > 0) {
      this.displayIngredients = this.rec.ingredientDetails;
      console.info(`[RecommendationCard] 使用已有配料数据: ${this.rec.name}, ${this.displayIngredients.length}个配料`);
    } else {
      // 懒加载配料详情
      console.info(`[RecommendationCard] 懒加载配料详情: ${this.rec.name}`);
      this.fetchIngredientDetails();
    }
  }
  
  private async fetchIngredientDetails() {
    if (this.isFetchingDetails) return;
    
    this.isFetchingDetails = true;
    try {
      const apiService = APIService.getInstance();
      const detail = await apiService.fetchRecipeDetail(this.rec.id);
      
      if (detail && detail['ingredients']) {
        const rawIngs: ESObject = detail['ingredients'];
        if (Array.isArray(rawIngs)) {
          this.displayIngredients = rawIngs as APIIngredient[];
          console.info(`[RecommendationCard] 获取到配料详情: ${this.displayIngredients.length}个`);
        }
      }
    } catch (error) {
      console.error(`[RecommendationCard] 获取配料详情失败:`, error);
    } finally {
      this.isFetchingDetails = false;
    }
  }
  
  private navigateToDetail() {
    router.pushUrl({
      url: '@bundle:com.example.cybar/entry/ets/pages/RecipeDetailPage',
      params: {
        recipeId: this.rec.id
      }
    }).catch((error: Error) => {
      console.error('[RecommendationCard] Navigation failed:', error);
      promptAction.showToast({ message: '跳转失败' });
    });
  }
  
  build() {
    Column({ space: 12 }) {
      // 顶部区域:匹配圆圈 + 基本信息
      Row({ space: 16 }) {
        // 左侧:匹配度圆环
        this.buildMatchCircle(this.rec.matchPercentage)
        
        // 右侧:配方信息
        Column({ space: 6 }) {
          // 配方名称
          Text(this.rec.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          
          // 创建者和ABV
          Row({ space: 12 }) {
            Text(`👤 ${this.rec.createdBy}`)
              .fontSize(13)
              .fontColor('#666666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            
            Text(`${this.rec.estimatedAbv.toFixed(1)}% ABV`)
              .fontSize(12)
              .fontColor('#1890ff')
              .fontWeight(FontWeight.Medium)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor('rgba(24, 144, 255, 0.12)')
              .borderRadius(10)
          }
          .width('100%')
          
          // 互动数据
          Row({ space: 16 }) {
            Text(`❤️ ${this.rec.likeCount}`)
              .fontSize(12)
              .fontColor('#999999')
            
            Text(`⭐ ${this.rec.favoriteCount}`)
              .fontSize(12)
              .fontColor('#999999')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      
      // 推荐理由
      if (this.rec.reasons.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.rec.reasons, (reason: string) => {
            Row({ space: 8 }) {
              Text('✓')
                .fontSize(13)
                .fontColor('#52c41a')
                .fontWeight(FontWeight.Bold)
              
              Text(reason)
                .fontSize(13)
                .fontColor('#666666')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }, (reason: string) => reason)
        }
        .width('100%')
        .padding({ top: 4 })
      }
      
      Divider()
        .color('#E8E8E8')
        .strokeWidth(1)
      
      // 详细配料信息
      Column({ space: 8 }) {
        Text('配料详情')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        
        if (this.isFetchingDetails) {
          // 加载中状态
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#1890ff')
            Text('加载配料信息...')
              .fontSize(12)
              .fontColor('#999999')
          }
          .padding(12)
        } else if (this.displayIngredients.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.displayIngredients, (ing: APIIngredient) => {
              Row({ space: 10 }) {
                // 配料名称
                Text(ing.name)
                  .fontSize(13)
                  .fontColor('#333333')
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                // 用量和ABV
                Row({ space: 8 }) {
                  Text(`${ing.volume}ml`)
                    .fontSize(12)
                    .fontColor('#666666')
                    .fontWeight(FontWeight.Medium)
                  
                  if (ing.abv > 0) {
                    Text(`${ing.abv}%`)
                      .fontSize(11)
                      .fontColor('#999999')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('#F5F5F5')
                      .borderRadius(6)
                  }
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .backgroundColor('#FAFAFA')
              .borderRadius(8)
            }, (ing: APIIngredient) => ing.id || ing.name)
          }
          .width('100%')
        } else {
          Text(this.rec.ingredients || '暂无配料信息')
            .fontSize(13)
            .fontColor('#999999')
            .padding(8)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({
      radius: 12,
      color: '#00000015',
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => {
      this.navigateToDetail();
    })
  }
  
  /**
   * 匹配度圆圈 - 真实进度环
   */
  @Builder
  buildMatchCircle(percentage: number) {
    Stack() {
      // 使用 Progress 组件显示真实进度
      Progress({
        value: percentage,
        total: 100,
        type: ProgressType.Ring
      })
        .width(60)
        .height(60)
        .color('#52c41a')
        .backgroundColor('#F0F0F0')
        .style({
          strokeWidth: 6
        })
      
      // 中心文字
      Column({ space: 2 }) {
        Text(`${percentage}%`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        
        Text('匹配')
          .fontSize(10)
          .fontColor('#999999')
      }
    }
    .width(60)
    .height(60)
  }
}
