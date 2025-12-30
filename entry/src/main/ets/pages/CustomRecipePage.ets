// CustomRecipePage.ets - 自定义配方创建页面
// 参考 Swift 版本 CustomRecipeView.swift 实现

import { router } from '@kit.ArkUI';
import APIService, { AIGeneratedRecipe, AIIngredient } from '../services/APIService';
import { APIIngredient } from '../models/Recipe';
import promptAction from '@ohos.promptAction';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';

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
  description?: string;
  steps?: string[];
}

@Component
export struct CustomRecipePage {
  // 深色模式支持
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  
  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }
  
  // 基础信息
  @State cocktailName: string = '';
  @State cocktailDescription: string = '';
  @State selectedImagePath: string = ''; // 选中的图片沙箱路径
  @State selectedImageFileName: string = ''; // 图片文件名（用于 internal:// 路径）
  @State imagePreviewUrl: string = ''; // 图片预览URL
  
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
  
  // AI智能调酒师状态
  @State showAISection: boolean = true;
  @State aiTasteDescription: string = '';
  @State aiOccasion: string = '';
  @State aiAlcoholStrength: string = '';
  @State isGeneratingAI: boolean = false;
  @State aiError: string = '';
  
  // 场合选项
  private occasionOptions: string[] = ['派对聚会', '浪漫约会', '商务社交', '独自放松', '节日庆祝', '夏日消暑', '冬日温暖'];
  // 酒精强度选项
  private strengthOptions: string[] = ['无酒精', '低度(5%以下)', '中度(5-15%)', '中高度(15-25%)', '高度(25%以上)'];
  
  aboutToAppear() {
    this.loadIngredients();
  }
  
  /**
   * 选择酒单图片
   */
  private async selectCocktailImage() {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      
      if (!result.photoUris || result.photoUris.length === 0) {
        return;
      }
      
      const selectedUri = result.photoUris[0];
      console.info('[CustomRecipe] 用户选择了图片:', selectedUri);
      
      // 拷贝到沙箱
      const context = getContext(this) as common.UIAbilityContext;
      const fileName = `cocktail_temp_${Date.now()}.jpg`;
      const cacheDir = context.cacheDir;
      const targetPath = `${cacheDir}/${fileName}`;
      
      const file = fs.openSync(selectedUri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(file.fd, targetPath);
      fs.closeSync(file);
      
      this.selectedImagePath = targetPath;
      this.selectedImageFileName = fileName;
      this.imagePreviewUrl = selectedUri; // 用原始URI做预览
      
      console.info('[CustomRecipe] 图片已拷贝到沙箱:', targetPath);
      console.info('[CustomRecipe] 文件名:', fileName);
      promptAction.showToast({ message: '图片已选择' });
      
    } catch (error) {
      console.error('[CustomRecipe] 选择图片失败:', error);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }
  
  /**
   * 移除选中的图片
   */
  private removeCocktailImage() {
    // 清理沙箱文件
    if (this.selectedImagePath) {
      try {
        fs.unlinkSync(this.selectedImagePath);
      } catch (e) {
        console.error('[CustomRecipe] 删除临时图片失败:', e);
      }
    }
    this.selectedImagePath = '';
    this.selectedImageFileName = '';
    this.imagePreviewUrl = '';
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
   * AI生成配方
   */
  private async generateAIRecipe() {
    if (this.aiTasteDescription.trim().length === 0) {
      this.aiError = '请输入口味描述';
      return;
    }
    
    this.isGeneratingAI = true;
    this.aiError = '';
    
    try {
      const apiService = APIService.getInstance();
      const result = await apiService.generateAIRecipe(
        this.aiTasteDescription,
        this.aiOccasion.length > 0 ? this.aiOccasion : undefined,
        this.aiAlcoholStrength.length > 0 ? this.aiAlcoholStrength : undefined
      );
      
      // 填充生成的配方到表单
      this.applyAIRecipe(result);
      
      // 显示成功提示
      promptAction.showToast({
        message: result.isDemo ? 'AI配方生成成功(演示模式)' : 'AI配方生成成功！',
        duration: 2000
      });
      
      // 收起AI区域
      this.showAISection = false;
      
    } catch (error) {
      console.error('[CustomRecipe] AI生成失败:', error);
      if (error instanceof Error) {
        this.aiError = error.message;
      } else {
        this.aiError = 'AI生成配方失败，请稍后重试';
      }
    } finally {
      this.isGeneratingAI = false;
    }
  }
  
  /**
   * 将AI生成的配方应用到表单
   */
  private applyAIRecipe(recipe: AIGeneratedRecipe) {
    try {
      // 安全检查
      if (!recipe) {
        console.error('[CustomRecipe] 配方数据为空');
        this.aiError = '配方数据为空';
        return;
      }
      
      // 填充名称和描述
      this.cocktailName = recipe.name || 'AI特调';
      this.cocktailDescription = recipe.description || '';
      
      // 清空并填充配料
      this.selectedIngredients = [];
      if (recipe.ingredients && Array.isArray(recipe.ingredients) && recipe.ingredients.length > 0) {
        const timestamp = Date.now();
        for (let i = 0; i < recipe.ingredients.length; i++) {
          const ing = recipe.ingredients[i];
          if (ing && ing.name) {
            this.selectedIngredients.push({
              id: `ai_${i}_${timestamp}`,
              name: ing.name,
              volume: ing.volume || 30,
              abv: ing.abv || 0,
              unit: '毫升',
              category: ing.category || 'other'
            });
          }
        }
      }
      
      // 清空并填充步骤
      this.steps = [];
      if (recipe.steps && Array.isArray(recipe.steps) && recipe.steps.length > 0) {
        const timestamp = Date.now();
        for (let i = 0; i < recipe.steps.length; i++) {
          const step = recipe.steps[i];
          if (step && typeof step === 'string') {
            this.steps.push({
              id: `step_${i}_${timestamp}`,
              index: i + 1,
              text: step
            });
          }
        }
      }
      
      // 确保至少有一个步骤
      if (this.steps.length === 0) {
        this.steps = [{ id: '1', index: 1, text: '' }];
      }
      
      // 重新计算ABV
      this.recalculateAbv();
      
      console.info('[CustomRecipe] 配方已应用:', this.cocktailName);
    } catch (error) {
      console.error('[CustomRecipe] 应用配方失败:', error);
      this.aiError = '应用配方失败';
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
    
    // 至少需要一个有效步骤，避免空说明导致后端/详情页异常
    const normalizedSteps: StepEntry[] = this.steps
      .map((s, idx): StepEntry => ({ id: s.id, index: idx + 1, text: s.text.trim() }))
      .filter(s => s.text.length > 0);
    if (normalizedSteps.length === 0) {
      promptAction.showToast({ message: '请至少填写一个步骤' });
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
      
      // 规范化步骤 - 同时提供字符串和数组，兼容后端解析
      const instructions: string = normalizedSteps
        .map(s => `${s.index}. ${s.text}`)
        .join('\n');
      const stepsArray: string[] = normalizedSteps.map(s => s.text);
      
      // 调用API保存（带图片）
      const recipeData: CreateRecipeData = {
        name: this.cocktailName,
        instructions: instructions,
        estimatedAbv: this.estimatedAbv,
        ingredients: ingredients,
        description: this.cocktailDescription.trim(),
        steps: stepsArray
      };
      console.info('[CustomRecipe] 保存配方数据:', JSON.stringify(recipeData));
      
      // 如果有图片，使用带图片的接口
      if (this.selectedImagePath) {
        const context = getContext(this) as common.UIAbilityContext;
        console.info('[CustomRecipe] 准备上传图片, 路径:', this.selectedImagePath);
        console.info('[CustomRecipe] 文件名:', this.selectedImageFileName);
        await apiService.createRecipeWithImage(context, recipeData, this.selectedImagePath, this.selectedImageFileName);
      } else {
        await apiService.createRecipe(recipeData);
      }
      
      promptAction.showToast({ message: '配方保存成功!' });
      
      // 触发发现页面刷新
      const currentTrigger: number = (AppStorage.get<number>('recipesRefreshTrigger') as number) || 0;
      AppStorage.setOrCreate<number>('recipesRefreshTrigger', currentTrigger + 1);
      console.info('[CustomRecipe] 已触发配方列表刷新');

      // 跳转回主入口并切换到配方Tab，保持底部导航
      router.replaceUrl({ url: 'pages/Index', params: { targetTab: 1 } }).catch((e: Error) => {
        console.error('[CustomRecipe] 跳转配方列表失败:', e);
      });
      
      // 清空表单并重置状态，确保步骤区也被清空
      this.removeCocktailImage(); // 清理图片
      this.cocktailName = '';
      this.cocktailDescription = '';
      this.selectedIngredients = [];
      this.steps = [{ id: Date.now().toString(), index: 1, text: '' }];
      this.estimatedAbv = 0;
      this.abvDescription = '无酒精或低度酒精，适合任何人饮用';
      this.currentCategory = 'base_alcohol';
      this.ingredientSearch = '';
      this.aiTasteDescription = '';
      this.aiOccasion = '';
      this.aiAlcoholStrength = '';
      this.showAISection = true;
      
      // 不强制自动返回，避免导航导致的闪退，让用户自行返回或继续创建
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
            .fontColor(this.getColors().textPrimary)
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
          .fontColor(this.getColors().textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        // 占位
        Row().width(44).height(44)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.getColors().cardBackground)
      
      // 内容区域 - 滚动视图
      Scroll() {
        Column({ space: 24 }) {
          // AI智能调酒师
          this.buildAISection()
          
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
    .backgroundColor(this.getColors().background)
  }
  
  /**
   * AI智能调酒师区域
   */
  @Builder
  buildAISection() {
    Column({ space: 16 }) {
      // 标题栏 - 可展开/收起
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(20)
            .fontColor(['#1890ff'])
          Text('AI智能调酒师')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890ff')
        }
        
        Blank()
        
        Button() {
          Text(this.showAISection ? '收起' : '展开')
            .fontSize(13)
            .fontColor('#1890ff')
        }
        .type(ButtonType.Normal)
        .backgroundColor('rgba(24, 144, 255, 0.1)')
        .borderRadius(12)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.showAISection = !this.showAISection;
        })
      }
      .width('100%')
      
      // 说明文字
      Text('没有灵感？描述您想要的口味，让AI为您量身定制鸡尾酒配方')
        .fontSize(13)
        .fontColor(this.getColors().textSecondary)
      
      if (this.showAISection) {
        Column({ space: 14 }) {
          // 口味描述
          Column({ space: 6 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(14)
                .fontColor([this.getColors().textPrimary])
              Text('口味描述')
                .fontSize(14)
                .fontColor(this.getColors().textPrimary)
                .fontWeight(FontWeight.Medium)
            }
            
            TextArea({ 
              placeholder: '例如：我想要一款清爽的夏日鸡尾酒，带有柑橘香味，不要太甜，酒精度适中...', 
              text: this.aiTasteDescription 
            })
              .onChange((value: string) => {
                this.aiTasteDescription = value;
              })
              .backgroundColor(this.getColors().inputBackground)
              .fontColor(this.getColors().textPrimary)
              .borderRadius(8)
              .height(100)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          
          // 可选项 - 场合和酒精强度
          Row({ space: 12 }) {
            // 适用场合
            Column({ space: 6 }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.star'))
                  .fontSize(14)
                  .fontColor([this.getColors().textSecondary])
                Text('适用场合')
                  .fontSize(13)
                  .fontColor(this.getColors().textSecondary)
              }
              
              Select(this.occasionOptions.map(opt => ({ value: opt } as SelectOption)))
                .selected(this.occasionOptions.indexOf(this.aiOccasion))
                .value(this.aiOccasion.length > 0 ? this.aiOccasion : '请选择（可选）')
                .font({ size: 14 })
                .fontColor(this.getColors().textPrimary)
                .backgroundColor(this.getColors().inputBackground)
                .borderRadius(8)
                .onSelect((index: number) => {
                  this.aiOccasion = this.occasionOptions[index];
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            // 酒精强度
            Column({ space: 6 }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.bolt_fill'))
                  .fontSize(14)
                  .fontColor([this.getColors().textSecondary])
                Text('酒精强度')
                  .fontSize(13)
                  .fontColor(this.getColors().textSecondary)
              }
              
              Select(this.strengthOptions.map(opt => ({ value: opt } as SelectOption)))
                .selected(this.strengthOptions.indexOf(this.aiAlcoholStrength))
                .value(this.aiAlcoholStrength.length > 0 ? this.aiAlcoholStrength : '请选择（可选）')
                .font({ size: 14 })
                .fontColor(this.getColors().textPrimary)
                .backgroundColor(this.getColors().inputBackground)
                .borderRadius(8)
                .onSelect((index: number) => {
                  this.aiAlcoholStrength = this.strengthOptions[index];
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          
          // 错误提示
          if (this.aiError.length > 0) {
            Text(this.aiError)
              .fontSize(13)
              .fontColor('#FF3B30')
          }
          
          // 生成按钮
          Button() {
            if (this.isGeneratingAI) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(Color.White)
                Text('AI生成中...')
                  .fontSize(16)
                  .fontColor(Color.White)
              }
            } else {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.wand_and_stars'))
                  .fontSize(18)
                  .fontColor([Color.White])
                Text('生成AI配方')
                  .fontSize(16)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Medium)
              }
            }
          }
          .type(ButtonType.Normal)
          .backgroundColor(this.isGeneratingAI ? '#999999' : '#667eea')
          .borderRadius(25)
          .width('100%')
          .height(50)
          .enabled(!this.isGeneratingAI)
          .onClick(() => {
            this.generateAIRecipe();
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBackground)
    .borderRadius(12)
    .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 2 })
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
        .fontColor(this.getColors().textPrimary)
      
      Column({ space: 10 }) {
        Column({ space: 6 }) {
          Text('名称')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
          
          TextInput({ placeholder: '输入鸡尾酒名称', text: this.cocktailName })
            .onChange((value: string) => {
              this.cocktailName = value;
            })
            .backgroundColor(this.getColors().inputBackground)
            .fontColor(this.getColors().textPrimary)
            .borderRadius(8)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        
        Column({ space: 6 }) {
          Text('描述(可选)')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
          
          TextArea({ placeholder: '口味/风格简介', text: this.cocktailDescription })
            .onChange((value: string) => {
              this.cocktailDescription = value;
            })
            .backgroundColor(this.getColors().inputBackground)
            .fontColor(this.getColors().textPrimary)
            .borderRadius(8)
            .height(80)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        
        // 酒单图片
        Column({ space: 6 }) {
          Text('酒单图片(可选)')
            .fontSize(14)
            .fontColor(this.getColors().textSecondary)
          
          if (this.imagePreviewUrl) {
            // 已选择图片 - 显示预览
            Stack() {
              Image(this.imagePreviewUrl)
                .width('100%')
                .height(200)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
              
              // 删除按钮
              Button() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              .type(ButtonType.Circle)
              .backgroundColor('rgba(255, 59, 48, 0.9)')
              .width(40)
              .height(40)
              .position({ x: '90%', y: 10 })
              .translate({ x: '-50%' })
              .onClick(() => {
                this.removeCocktailImage();
              })
            }
            .width('100%')
            .height(200)
          } else {
            // 未选择 - 显示上传按钮
            Button() {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.camera'))
                  .fontSize(40)
                  .fontColor([this.getColors().textTertiary])
                
                Text('点击选择图片')
                  .fontSize(14)
                  .fontColor(this.getColors().textSecondary)
                
                Text('支持 JPG、PNG，不超过5MB')
                  .fontSize(11)
                  .fontColor(this.getColors().textTertiary)
              }
            }
            .type(ButtonType.Normal)
            .backgroundColor(this.getColors().secondaryBackground)
            .width('100%')
            .height(150)
            .borderRadius(8)
            .border({ width: 1, color: this.getColors().divider, style: BorderStyle.Dashed })
            .onClick(() => {
              this.selectCocktailImage();
            })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .padding(16)
      .backgroundColor(this.getColors().cardBackground)
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
        .fontColor(this.getColors().textPrimary)
      
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
          .backgroundColor(this.getColors().inputBackground)
        
        // 配料网格
        if (this.loadingIngredients) {
          Row() {
            LoadingProgress()
              .width(30)
              .height(30)
              .color('#1890ff')
            Text('加载配料...')
              .fontSize(14)
              .fontColor(this.getColors().textTertiary)
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
      .backgroundColor(this.getColors().cardBackground)
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
        .fontColor(this.isIngredientSelected(item.id) ? Color.White : this.getColors().textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      
      if (item.abv && item.abv > 0) {
        Text(`${item.abv}%`)
          .fontSize(11)
          .fontColor(this.isIngredientSelected(item.id) ? 'rgba(255,255,255,0.8)' : this.getColors().textTertiary)
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.isIngredientSelected(item.id) ? '#1890ff' : this.getColors().secondaryBackground)
    .borderRadius(8)
    .border({
      width: this.isIngredientSelected(item.id) ? 2 : 1,
      color: this.isIngredientSelected(item.id) ? '#1890ff' : this.getColors().divider
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
        .fontColor(this.getColors().textPrimary)
        .margin({ top: 12 })
      
      // 按分类分组显示
      ForEach(this.categoryOrder, (cat: string) => {
        if (this.getSelectedByCategory(cat).length > 0) {
          Column({ space: 8 }) {
            Text(this.categoryNames[cat] || cat)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getColors().textSecondary)
            
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
        .fontColor(this.getColors().textPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      // 用量输入
      TextInput({ text: ing.volume.toString() })
        .type(InputType.Number)
        .width(70)
        .height(36)
        .fontSize(13)
        .backgroundColor(this.getColors().inputBackground)
        .fontColor(this.getColors().textPrimary)
        .borderRadius(6)
        .onChange((value: string) => {
          const num = parseFloat(value);
          if (!isNaN(num) && num >= 0) {
            this.updateIngredientVolume(ing.id, num);
          }
        })
      
      Text(ing.unit)
        .fontSize(12)
        .fontColor(this.getColors().textTertiary)
        .width(40)
      
      // 删除按钮
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor(['#FF3B30'])
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
    .backgroundColor(this.getColors().secondaryBackground)
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
        .fontColor(this.getColors().textPrimary)
      
      Row({ space: 16 }) {
        // ABV数值显示
        Column({ space: 4 }) {
          Text(this.estimatedAbv.toFixed(1))
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890ff')
          
          Text('% ABV')
            .fontSize(14)
            .fontColor(this.getColors().textTertiary)
        }
        
        Divider()
          .vertical(true)
          .height(60)
          .color(this.getColors().divider)
        
        // 描述
        Text(this.abvDescription)
          .fontSize(14)
          .fontColor(this.getColors().textSecondary)
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getColors().cardBackground)
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
        .fontColor(this.getColors().textPrimary)
      
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
              .backgroundColor(this.getColors().inputBackground)
              .fontColor(this.getColors().textPrimary)
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
      .backgroundColor(this.getColors().cardBackground)
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
