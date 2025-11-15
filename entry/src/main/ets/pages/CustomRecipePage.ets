// CustomRecipePage.ets - 自定义配方创建页面
// 参考 Swift 版本 CustomRecipeView.swift 实现

import { router } from '@kit.ArkUI';
import APIService from '../services/APIService';
import { APIIngredient } from '../common/models/Recipe';
import promptAction from '@ohos.promptAction';

// 配料项接口
interface IngredientItem {
  id: string;
  name: string;
  abv?: number;
  unit?: string;
  category?: string;
  volume?: number;
}

// 已选配料接口
interface SelectedIngredient {
  id: string;
  name: string;
  volume: number;
  abv: number;
  unit: string;
  category: string;
}

// 步骤接口
interface StepEntry {
  id: string;
  index: number;
  text: string;
}

// 保存配方时的配料数据接口
interface RecipeIngredientData {
  id: string;
  name: string;
  volume: number;
  abv: number;
}

// 保存配方的请求数据接口
interface CreateRecipeData {
  name: string;
  instructions: string;
  estimatedAbv: number;
  ingredients: RecipeIngredientData[];
}

@Component
export struct CustomRecipePage {
  // 基础信息
  @State cocktailName: string = '';
  @State cocktailDescription: string = '';
  
  // 分类和原料
  private categoryOrder: string[] = [
    'base_alcohol', 'liqueurs', 'vermouth_wine', 'bitters',
    'juice', 'syrup', 'soda_mixer', 'dairy_cream', 'other'
  ];
  
  private categoryNames: Record<string, string> = {
    'base_alcohol': '基酒',
    'liqueurs': '力娇酒/利口酒',
    'vermouth_wine': '味美思/加强葡萄酒',
    'bitters': '苦精',
    'juice': '果汁',
    'syrup': '糖浆',
    'soda_mixer': '碳酸/调配饮料',
    'dairy_cream': '奶制品',
    'other': '其他'
  };
  
  @State currentCategory: string = 'base_alcohol';
  @State ingredientSearch: string = '';
  @State allIngredients: IngredientItem[] = [];
  @State loadingIngredients: boolean = false;
  @State ingredientLoadError: string = '';
  
  // 已选择的配料
  @State selectedIngredients: SelectedIngredient[] = [];
  
  // 制作步骤
  @State steps: StepEntry[] = [{ id: '1', index: 1, text: '' }];
  
  // ABV 计算
  @State estimatedAbv: number = 0.0;
  @State abvDescription: string = '无酒精或低度酒精，适合任何人饮用';
  
  // 保存状态
  @State isSaving: boolean = false;
  @State saveMessage: string = '';
  
  aboutToAppear() {
    this.loadIngredients();
  }
  
  /**
   * 加载原料列表
   */
  private async loadIngredients() {
    if (this.loadingIngredients) return;
    
    this.loadingIngredients = true;
    this.ingredientLoadError = '';
    
    try {
      const apiService = APIService.getInstance();
      const result = await apiService.fetchCustomIngredients();
      
      // 解析原料数据
      const ingredients: IngredientItem[] = [];
      const ingredientsField: ESObject = Reflect.get(result, 'ingredients') as ESObject;
      if (ingredientsField) {
        const cats: ESObject[] = ingredientsField as ESObject[];
        cats.forEach((cat: ESObject) => {
          const items: ESObject[] = Reflect.get(cat, 'items') as ESObject[];
          const category: string = Reflect.get(cat, 'category') as string;
          
          if (items) {
            items.forEach((item: ESObject) => {
              const ingredientId: string = Reflect.get(item, 'id') as string;
              const ingredientName: string = Reflect.get(item, 'name') as string;
              const ingredientAbv: number = Reflect.get(item, 'abv') as number;
              const ingredientUnit: string = Reflect.get(item, 'unit') as string;
              
              ingredients.push({
                id: ingredientId,
                name: ingredientName,
                abv: ingredientAbv,
                unit: ingredientUnit,
                category: category
              });
            });
          }
        });
      }
      
      this.allIngredients = ingredients;
      console.info(`[CustomRecipe] 加载了 ${ingredients.length} 个配料`);
      
    } catch (error) {
      console.error('[CustomRecipe] 加载配料失败:', error);
      this.ingredientLoadError = '加载配料失败';
    } finally {
      this.loadingIngredients = false;
    }
  }
  
  /**
   * 获取当前分类的配料(过滤后)
   */
  private getFilteredIngredients(): IngredientItem[] {
    let items = this.allIngredients.filter(item => item.category === this.currentCategory);
    
    if (this.ingredientSearch.trim().length > 0) {
      const query = this.ingredientSearch.toLowerCase();
      items = items.filter(item => 
        item.name.toLowerCase().includes(query) || 
        item.id.toLowerCase().includes(query)
      );
    }
    
    return items;
  }
  
  /**
   * 获取指定分类的已选配料
   */
  private getSelectedByCategory(category: string): SelectedIngredient[] {
    return this.selectedIngredients.filter(ing => ing.category === category);
  }
  
  /**
   * 切换配料选择
   */
  private toggleIngredient(item: IngredientItem) {
    const index = this.selectedIngredients.findIndex(ing => ing.id === item.id);
    
    if (index >= 0) {
      // 移除
      this.selectedIngredients.splice(index, 1);
    } else {
      // 添加
      const defaultVolume = this.getDefaultVolume(item);
      this.selectedIngredients.push({
        id: item.id,
        name: item.name,
        volume: defaultVolume,
        abv: item.abv || 0,
        unit: item.unit || '毫升',
        category: item.category || 'other'
      });
    }
    
    this.recalculateAbv();
  }
  
  /**
   * 获取默认用量
   */
  private getDefaultVolume(item: IngredientItem): number {
    const unit = (item.unit || '').toLowerCase();
    if (unit.includes('滴') || unit.includes('drop')) return 3;
    if (unit.includes('片') || unit.includes('slice')) return 1;
    if (unit.includes('个') || unit.includes('piece')) return 1;
    return 30; // 默认30ml
  }
  
  /**
   * 判断配料是否已选
   */
  private isIngredientSelected(id: string): boolean {
    return this.selectedIngredients.some(ing => ing.id === id);
  }
  
  /**
   * 更新配料用量
   */
  private updateIngredientVolume(id: string, volume: number) {
    const ing = this.selectedIngredients.find(i => i.id === id);
    if (ing) {
      ing.volume = volume;
      this.recalculateAbv();
    }
  }
  
  /**
   * 移除配料
   */
  private removeIngredient(id: string) {
    const index = this.selectedIngredients.findIndex(ing => ing.id === id);
    if (index >= 0) {
      this.selectedIngredients.splice(index, 1);
      this.recalculateAbv();
    }
  }
  
  /**
   * 重新计算ABV
   */
  private recalculateAbv() {
    let totalAlcohol = 0;
    let totalVolume = 0;
    
    this.selectedIngredients.forEach(ing => {
      // 只计算液体(有ml单位的)
      if (ing.unit.includes('毫升') || ing.unit.toLowerCase().includes('ml')) {
        totalVolume += ing.volume;
        totalAlcohol += (ing.volume * ing.abv / 100);
      }
    });
    
    if (totalVolume > 0) {
      this.estimatedAbv = (totalAlcohol / totalVolume) * 100;
    } else {
      this.estimatedAbv = 0;
    }
    
    // 更新描述
    if (this.estimatedAbv < 5) {
      this.abvDescription = '无酒精或低度酒精，适合任何人饮用';
    } else if (this.estimatedAbv < 15) {
      this.abvDescription = '低度酒精饮品，口感温和';
    } else if (this.estimatedAbv < 25) {
      this.abvDescription = '中度酒精，经典鸡尾酒强度';
    } else if (this.estimatedAbv < 35) {
      this.abvDescription = '较高酒精度，请适量饮用';
    } else {
      this.abvDescription = '高度酒精饮品，务必谨慎';
    }
  }
  
  /**
   * 添加步骤
   */
  private addStep() {
    const newIndex = this.steps.length + 1;
    this.steps.push({
      id: Date.now().toString(),
      index: newIndex,
      text: ''
    });
  }
  
  /**
   * 移除步骤
   */
  private removeStep(id: string) {
    if (this.steps.length <= 1) return;
    
    const index = this.steps.findIndex(s => s.id === id);
    if (index >= 0) {
      this.steps.splice(index, 1);
      // 重新编号
      this.steps.forEach((step, idx) => {
        step.index = idx + 1;
      });
    }
  }
  
  /**
   * 更新步骤文本
   */
  private updateStepText(id: string, text: string) {
    const step = this.steps.find(s => s.id === id);
    if (step) {
      step.text = text;
    }
  }
  
  /**
   * 检查是否可以保存
   */
  private canSave(): boolean {
    return this.cocktailName.trim().length > 0 && 
           this.selectedIngredients.length > 0 &&
           !this.isSaving;
  }
  
  /**
   * 保存配方
   */
  private async saveCocktail() {
    if (!this.canSave()) {
      promptAction.showToast({ message: '请填写名称并选择配料' });
      return;
    }
    
    this.isSaving = true;
    
    try {
      const apiService = APIService.getInstance();
      
      // 构建配料数组
      const ingredients: RecipeIngredientData[] = this.selectedIngredients.map(ing => {
        const data: RecipeIngredientData = {
          id: ing.id,
          name: ing.name,
          volume: ing.volume,
          abv: ing.abv
        };
        return data;
      });
      
      // 构建步骤字符串
      const instructions = this.steps
        .filter(s => s.text.trim().length > 0)
        .map(s => `${s.index}. ${s.text}`)
        .join('\n');
      
      // 调用API保存
      const recipeData: CreateRecipeData = {
        name: this.cocktailName,
        instructions: instructions,
        estimatedAbv: this.estimatedAbv,
        ingredients: ingredients
      };
      const result = await apiService.createRecipe(recipeData);
      
      promptAction.showToast({ message: '配方保存成功!' });
      
      // 延迟后返回
      setTimeout(() => {
        router.back();
      }, 1000);
      
    } catch (error) {
      console.error('[CustomRecipe] 保存失败:', error);
      const message = error instanceof Error ? error.message : '保存失败';
      promptAction.showToast({ message: message });
    } finally {
      this.isSaving = false;
    }
  }
  
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button() {
          Text('←')
            .fontSize(24)
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .width(44)
        .height(44)
        .onClick(() => {
          router.back();
        })
        
        Text('自定义配方')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        // 占位
        Row().width(44).height(44)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      
      // 内容区域 - 滚动视图
      Scroll() {
        Column({ space: 24 }) {
          // 基本信息
          this.buildBasicInfoSection()
          
          // 原料选择
          this.buildIngredientSection()
          
          // ABV计算
          this.buildAbvSection()
          
          // 制作步骤
          this.buildStepsSection()
          
          // 保存按钮
          this.buildSaveButton()
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
  
  /**
   * 基本信息区域
   */
  @Builder
  buildBasicInfoSection() {
    Column({ space: 12 }) {
      Text('基本信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
      
      Column({ space: 10 }) {
        Column({ space: 6 }) {
          Text('名称')
            .fontSize(14)
            .fontColor('#666666')
          
          TextInput({ placeholder: '输入鸡尾酒名称', text: this.cocktailName })
            .onChange((value: string) => {
              this.cocktailName = value;
            })
            .backgroundColor(Color.White)
            .borderRadius(8)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        
        Column({ space: 6 }) {
          Text('描述(可选)')
            .fontSize(14)
            .fontColor('#666666')
          
          TextArea({ placeholder: '口味/风格简介', text: this.cocktailDescription })
            .onChange((value: string) => {
              this.cocktailDescription = value;
            })
            .backgroundColor(Color.White)
            .borderRadius(8)
            .height(80)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  
  /**
   * 原料选择区域
   */
  @Builder
  buildIngredientSection() {
    Column({ space: 12 }) {
      Text('原料选择')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
      
      Column({ space: 12 }) {
        // 分类标签
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.categoryOrder, (cat: string) => {
              Button() {
                Text(this.categoryNames[cat] || cat)
                  .fontSize(13)
                  .fontColor(this.currentCategory === cat ? Color.White : '#1890ff')
              }
              .type(ButtonType.Capsule)
              .backgroundColor(this.currentCategory === cat ? '#1890ff' : 'rgba(24, 144, 255, 0.15)')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .onClick(() => {
                this.currentCategory = cat;
              })
            }, (cat: string) => cat)
          }
          .padding({ top: 4, bottom: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        
        // 搜索框
        Search({ placeholder: '搜索当前分类原料', value: this.ingredientSearch })
          .onChange((value: string) => {
            this.ingredientSearch = value;
          })
          .backgroundColor(Color.White)
        
        // 配料网格
        if (this.loadingIngredients) {
          Row() {
            LoadingProgress()
              .width(30)
              .height(30)
              .color('#1890ff')
            Text('加载配料...')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ left: 10 })
          }
          .padding(20)
          .justifyContent(FlexAlign.Center)
        } else if (this.ingredientLoadError) {
          Text(this.ingredientLoadError)
            .fontSize(14)
            .fontColor('#FF3B30')
            .padding(20)
        } else {
          this.buildIngredientGrid()
        }
        
        // 已选配料列表
        if (this.selectedIngredients.length > 0) {
          this.buildSelectedIngredientsList()
        }
      }
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  
  /**
   * 配料网格
   */
  @Builder
  buildIngredientGrid() {
    if (this.getFilteredIngredients().length === 0) {
      Text('无匹配配料')
        .fontSize(14)
        .fontColor('#999999')
        .padding(20)
        .width('100%')
        .textAlign(TextAlign.Center)
    } else {
      GridRow({ columns: 3, gutter: 10 }) {
        ForEach(this.getFilteredIngredients(), (item: IngredientItem) => {
          GridCol() {
            this.buildIngredientCard(item)
          }
        }, (item: IngredientItem) => item.id)
      }
    }
  }
  
  /**
   * 配料卡片
   */
  @Builder
  buildIngredientCard(item: IngredientItem) {
    Column({ space: 6 }) {
      Text(item.name)
        .fontSize(13)
        .fontColor(this.isIngredientSelected(item.id) ? Color.White : '#333333')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      
      if (item.abv && item.abv > 0) {
        Text(`${item.abv}%`)
          .fontSize(11)
          .fontColor(this.isIngredientSelected(item.id) ? 'rgba(255,255,255,0.8)' : '#999999')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.isIngredientSelected(item.id) ? '#1890ff' : '#F5F5F5')
    .borderRadius(8)
    .border({
      width: this.isIngredientSelected(item.id) ? 2 : 1,
      color: this.isIngredientSelected(item.id) ? '#1890ff' : '#E8E8E8'
    })
    .onClick(() => {
      this.toggleIngredient(item);
    })
  }
  
  /**
   * 已选配料列表
   */
  @Builder
  buildSelectedIngredientsList() {
    Column({ space: 12 }) {
      Text('已选配料')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ top: 12 })
      
      // 按分类分组显示
      ForEach(this.categoryOrder, (cat: string) => {
        if (this.getSelectedByCategory(cat).length > 0) {
          Column({ space: 8 }) {
            Text(this.categoryNames[cat] || cat)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#666666')
            
            ForEach(this.getSelectedByCategory(cat), (ing: SelectedIngredient) => {
              this.buildSelectedIngredientRow(ing)
            }, (ing: SelectedIngredient) => ing.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }, (cat: string) => cat)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  
  /**
   * 已选配料行
   */
  @Builder
  buildSelectedIngredientRow(ing: SelectedIngredient) {
    Row({ space: 10 }) {
      // 配料名称
      Text(ing.name)
        .fontSize(14)
        .fontColor('#333333')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      // 用量输入
      TextInput({ text: ing.volume.toString() })
        .type(InputType.Number)
        .width(70)
        .height(36)
        .fontSize(13)
        .backgroundColor('#F5F5F5')
        .borderRadius(6)
        .onChange((value: string) => {
          const num = parseFloat(value);
          if (!isNaN(num) && num >= 0) {
            this.updateIngredientVolume(ing.id, num);
          }
        })
      
      Text(ing.unit)
        .fontSize(12)
        .fontColor('#999999')
        .width(40)
      
      // 删除按钮
      Button() {
        Text('✕')
          .fontSize(16)
          .fontColor('#FF3B30')
      }
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .width(32)
      .height(32)
      .onClick(() => {
        this.removeIngredient(ing.id);
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FAFAFA')
    .borderRadius(8)
  }
  
  /**
   * ABV计算区域
   */
  @Builder
  buildAbvSection() {
    Column({ space: 12 }) {
      Text('酒精度计算')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
      
      Row({ space: 16 }) {
        // ABV数值显示
        Column({ space: 4 }) {
          Text(this.estimatedAbv.toFixed(1))
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890ff')
          
          Text('% ABV')
            .fontSize(14)
            .fontColor('#999999')
        }
        
        Divider()
          .vertical(true)
          .height(60)
          .color('#E8E8E8')
        
        // 描述
        Text(this.abvDescription)
          .fontSize(14)
          .fontColor('#666666')
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  
  /**
   * 制作步骤区域
   */
  @Builder
  buildStepsSection() {
    Column({ space: 12 }) {
      Text('制作步骤')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
      
      Column({ space: 10 }) {
        ForEach(this.steps, (step: StepEntry) => {
          Row({ space: 10 }) {
            Text(`${step.index}.`)
              .fontSize(16)
              .fontColor('#1890ff')
              .fontWeight(FontWeight.Medium)
              .width(30)
              .textAlign(TextAlign.End)
            
            TextArea({ placeholder: '步骤内容', text: step.text })
              .onChange((value: string) => {
                this.updateStepText(step.id, value);
              })
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .layoutWeight(1)
              .height(60)
            
            if (this.steps.length > 1) {
              Button() {
                Text('−')
                  .fontSize(20)
                  .fontColor('#FF3B30')
              }
              .type(ButtonType.Circle)
              .backgroundColor('rgba(255,59,48,0.1)')
              .width(36)
              .height(36)
              .onClick(() => {
                this.removeStep(step.id);
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (step: StepEntry) => step.id)
        
        // 添加步骤按钮
        Button() {
          Row({ space: 6 }) {
            Text('+')
              .fontSize(18)
            Text('添加步骤')
              .fontSize(14)
          }
        }
        .type(ButtonType.Normal)
        .backgroundColor('rgba(24, 144, 255, 0.15)')
        .fontColor('#1890ff')
        .borderRadius(8)
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .onClick(() => {
          this.addStep();
        })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  
  /**
   * 保存按钮
   */
  @Builder
  buildSaveButton() {
    Button() {
      Row({ space: 10 }) {
        if (this.isSaving) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Color.White)
        }
        
        Text(this.isSaving ? '保存中...' : '保存配方')
          .fontSize(16)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
    }
    .type(ButtonType.Normal)
    .backgroundColor(this.canSave() ? '#52c41a' : '#D8D8D8')
    .width('100%')
    .height(50)
    .borderRadius(12)
    .enabled(this.canSave())
    .onClick(() => {
      this.saveCocktail();
    })
  }
}
