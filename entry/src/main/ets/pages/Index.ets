// Index.ets - 主页面入口(底部导航栏架构)
// 对应 Swift 项目中的 ContentView.swift

import { RecipesPage } from './RecipesPage';
import { RecommendationsPage } from './RecommendationsPage';
import { CustomRecipePage } from './CustomRecipePage';
import { UserProfilePage } from './UserProfilePage';
import { SearchPage } from './SearchPage';

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;
  @State showSearch: boolean = false;
  @State searchText: string = '';
  
  @Builder
  TabBuilder(index: number, title: string, icon: Resource, selectedIcon: Resource) {
    Column() {
      Image(this.currentTabIndex === index ? selectedIcon : icon)
        .size({ width: 24, height: 24 })
        .fillColor(this.currentTabIndex === index ? '#007DFF' : '#999999')
      
      Text(title)
        .fontSize(10)
        .fontColor(this.currentTabIndex === index ? '#007DFF' : '#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  
  build() {
    Stack() {
      // 主 Tabs 导航
      Tabs({
        barPosition: BarPosition.End,
        index: this.currentTabIndex
      }) {
        // 推荐页
        TabContent() {
          RecommendationsPage()
        }
        .tabBar(this.TabBuilder(0, '推荐', $r('sys.symbol.star'), $r('sys.symbol.star')))
        
        // 配方列表
        TabContent() {
          RecipesPage()
        }
        .tabBar(this.TabBuilder(1, '配方', $r('sys.symbol.list_bullet'), $r('sys.symbol.list_bullet')))
        
        // 新配方
        TabContent() {
          CustomRecipePage()
        }
        .tabBar(this.TabBuilder(2, '新配方', $r('sys.symbol.plus_square'), $r('sys.symbol.plus_square')))
        
        // 用户中心
        TabContent() {
          UserProfilePage()
        }
        .tabBar(this.TabBuilder(3, '我的', $r('sys.symbol.person'), $r('sys.symbol.person')))
        
        // 搜索页
        TabContent() {
          SearchPage({ 
            onClose: () => {
              this.showSearch = false;
              this.currentTabIndex = 1; // 返回配方列表
            }
          })
        }
        .tabBar(this.TabBuilder(4, '搜索', $r('sys.symbol.magnifyingglass'), $r('sys.symbol.magnifyingglass')))
      }
      .onChange((index: number) => {
        this.currentTabIndex = index;
        // 如果切换到搜索标签页,显示搜索界面
        if (index === 4) {
          this.showSearch = true;
        }
      })
      .width('100%')
      .height('100%')
      .barMode(BarMode.Fixed)
      .barHeight(56)
      
      // // 悬浮搜索按钮(当不在搜索页时显示)
      // if (!this.showSearch && this.currentTabIndex !== 4) {
      //   Button({ type: ButtonType.Circle }) {
      //     Image($r('sys.symbol.magnifyingglass'))
      //       .width(24)
      //       .height(24)
      //       .fillColor('#FFFFFF')
      //   }
      //   .width(56)
      //   .height(56)
      //   .backgroundColor('#007DFF')
      //   .position({ x: '85%', y: '80%' })
      //   .shadow({
      //     radius: 10,
      //     color: 'rgba(0, 125, 255, 0.3)',
      //     offsetX: 0,
      //     offsetY: 4
      //   })
      //   .onClick(() => {
      //     this.showSearch = true;
      //     this.currentTabIndex = 4;
      //   })
      // }
    }
    .width('100%')
    .height('100%')
  }
}