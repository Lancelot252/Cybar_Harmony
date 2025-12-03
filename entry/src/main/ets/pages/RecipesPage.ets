// RecipesPage.ets - 配方列表页面

import { apiService } from '../services/APIService';
import { Recipe, RecipesResponse, Ingredient } from '../models/Recipe';
import { router } from '@kit.ArkUI';

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
  
  private pageSize: number = 10; 
  private sortType: string = 'default';

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
      
      if (reset) {
        this.recipesDataSource.setData(newRecipes);
      } else {
        this.recipesDataSource.addData(newRecipes);
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

  build() {
    Column() {
      // Header
      Row() {
        Text('发现') 
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(Color.White)

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
        .padding({ left: 10, right: 10, top: 10, bottom: 10 }) // 增加外边距，确保两边不贴边
        .width('100%')
        .height('100%')
        .onReachEnd(() => {
            this.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F6F6')
  }
}

/**
 * 配方卡片组件
 */
@Component
struct RecipeCard {
  @Prop recipe: Recipe;
  onTap?: () => void;
  
  build() {
    Column() {
      // Image Area
      Image($r('app.media.wine'))
        .width('100%') // 确保图片填满卡片宽度
        .height(180)   // 稍微调小一点高度，让比例更协调
        .objectFit(ImageFit.Cover)
        .borderRadius({ topLeft: 8, topRight: 8 })
      
      // Content
      Column() {
        // 标题区域
        Text(this.recipe.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .maxLines(3) // 作者最多3行但要注意高度
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor('#333')
          .width('100%') // 确保文本容器占满
          .textAlign(TextAlign.Start)
        
        // Tags (ABV + Ingredients)
        Row({ space: 4 }) {
            Text(`${this.recipe.estimatedAbv.toFixed(0)}%`)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FF6B00')
                .backgroundColor('#FFF0E0')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4)
                .flexShrink(0)
            
            // Ingredients preview (first 5)
            if (this.recipe.ingredients && typeof this.recipe.ingredients === 'string') {
                Text(this.recipe.ingredients.split(',').slice(0, 5).join(' '))
                    .fontSize(10)
                    .fontColor('#999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1) // 让配料文字占据剩余空间
            }
        }
        .margin({ top: 6 })
        .width('100%')
        
        // Footer (User + Likes)
        Row() {
            // 左边：头像+名字
            Row({ space: 4 }) {
                Image($r('app.media.startIcon')) 
                    .width(16)
                    .height(16)
                    .borderRadius(8)
                    .flexShrink(0) // 头像不许压缩
                
                Text(this.recipe.createdBy)
                    .fontSize(10)
                    .fontColor('#666')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 这里不设 layoutWeight，让它自然显示，但受限于外层 Row
            }
            .layoutWeight(1) // 让左侧信息占据主要空间
            .alignItems(VerticalAlign.Center)
            
            // 右边：点赞数量
            Row({ space: 2 }) {
                Text(this.recipe.isLiked ? '❤️' : '🤍')
                    .fontSize(12)
                Text(`${this.recipe.likeCount}`)
                    .fontSize(12)
                    .fontColor('#666')
            }
            .flexShrink(0) // 点赞部分不许压缩，必须完整显示
            .margin({ left: 4 }) // 给左边留点距离
        }
        .margin({ top: 8 })
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween) // 左右两端对齐

      }
      .padding(8)
      .backgroundColor(Color.White)
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      .alignItems(HorizontalAlign.Start) // 内容左对齐
    }
    .width('100%') // 卡片占满 FlowItem 给的宽度
    .borderRadius(8)
    .backgroundColor(Color.White)
    .shadow({ radius: 4, color: '#1A000000', offsetY: 2 }) // 加一点阴影，增加立体感
    .onClick(() => {
        if (this.onTap) this.onTap();
    })
  }
}
