// AdminPage.ets - 管理员控制台
// 参考 demo 实现，适配 HarmonyOS Next

import { router } from '@kit.ArkUI';
import promptAction from '@ohos.promptAction';
import APIService, { User, AdminRecipe, AdminComment, AdminStats } from '../services/APIService';
import { ThemeManager, LightTheme, DarkTheme, ThemeColors } from '../common/ThemeManager';

@Entry
@Component
export struct AdminPage {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State currentTabIndex: number = 0;

  // 统计数据
  @State totalUsers: number = 0;
  @State totalRecipes: number = 0;

  // 列表数据
  @State userList: User[] = [];
  @State recipeList: AdminRecipe[] = [];
  @State commentList: AdminComment[] = [];

  // 加载状态
  @State isLoading: boolean = false;

  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme;
  }

  aboutToAppear(): void {
    // 检查是否是管理员
    const apiService = APIService.getInstance();
    if (!apiService.isLoggedIn || !apiService.currentUser || apiService.currentUser.role !== 'admin') {
      promptAction.showToast({ message: '无权访问管理员页面' });
      router.back();
      return;
    }
    this.refreshAll();
  }

  async refreshAll(): Promise<void> {
    this.isLoading = true;
    try {
      // 先并发加载列表数据
      await Promise.all([
        this.loadUsers(),
        this.loadRecipes(),
        this.loadComments()
      ]);
      
      // 再单独加载统计数据，确保UI更新
      await this.loadStats();
    } finally {
      this.isLoading = false;
    }
  }

  async loadStats(): Promise<void> {
    try {
      const result: AdminStats = await APIService.getInstance().getAdminStats();
      console.info('[AdminPage] 统计数据原始返回:', JSON.stringify(result));
      
      // 直接赋值数字
      this.totalUsers = Number(result.totalUsers) || 0;
      this.totalRecipes = Number(result.totalRecipes) || 0;
      
      console.info(`[AdminPage] UI状态已更新: totalUsers=${this.totalUsers}, totalRecipes=${this.totalRecipes}`);
    } catch (error) {
      console.error('[AdminPage] 加载统计数据失败:', error);
      promptAction.showToast({ message: '加载统计数据失败: ' + (error instanceof Error ? error.message : String(error)) });
    }
  }

  async loadUsers(): Promise<void> {
    try {
      this.userList = await APIService.getInstance().getAllUsers();
      console.info(`[AdminPage] 加载了 ${this.userList.length} 个用户`);
    } catch (error) {
      console.error('[AdminPage] 加载用户列表失败:', error);
    }
  }

  async loadRecipes(): Promise<void> {
    try {
      this.recipeList = await APIService.getInstance().getAllRecipesForAdmin();
      console.info(`[AdminPage] 加载了 ${this.recipeList.length} 个配方`);
    } catch (error) {
      console.error('[AdminPage] 加载配方列表失败:', error);
    }
  }

  async loadComments(): Promise<void> {
    try {
      this.commentList = await APIService.getInstance().getAdminComments();
      console.info(`[AdminPage] 加载了 ${this.commentList.length} 条评论`);
    } catch (error) {
      console.error('[AdminPage] 加载评论列表失败:', error);
    }
  }

  async confirmAndDelete(
    title: string,
    message: string,
    deleteFn: () => Promise<boolean>,
    refreshFn: () => void
  ): Promise<void> {
    promptAction.showDialog({
      title: title,
      message: message,
      buttons: [
        { text: '取消', color: '#007DFF' },
        { text: '删除', color: '#FF0000' }
      ]
    }, async (err, data) => {
      if (err || data.index === 0) return;
      if (data.index === 1) {
        const success = await deleteFn();
        if (success) {
          promptAction.showToast({ message: '删除成功' });
          refreshFn();
          await this.loadStats();
        } else {
          promptAction.showToast({ message: '删除失败' });
        }
      }
    });
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

        Text('管理员控制台')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().textPrimary)
          .layoutWeight(1)
          .margin({ left: 8 })

        // 刷新按钮
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([this.getColors().textPrimary])
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .width(44)
        .height(44)
        .onClick(() => {
          this.refreshAll();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.getColors().cardBackground)
      .shadow({ radius: 2, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.05)', offsetY: 1 })

      // Tab 内容
      Tabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
        TabContent() {
          this.DashboardView()
        }.tabBar('概览')

        TabContent() {
          this.UserListView()
        }.tabBar('用户')

        TabContent() {
          this.RecipeListView()
        }.tabBar('配方')

        TabContent() {
          this.CommentListView()
        }.tabBar('评论')
      }
      .vertical(false)
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(50)
      .animationDuration(200)
      .backgroundColor(this.getColors().background)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
  }

  @Builder
  DashboardView() {
    Scroll() {
      Column({ space: 16 }) {
        // 统计卡片 - 改用 Row + Flex 布局
        Row({ space: 16 }) {
          Column({ space: 8 }) {
            Text(`${this.totalUsers}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')

            Text('用户总数')
              .fontSize(14)
              .fontColor(this.getColors().textSecondary)
          }
          .width('48%')
          .padding(24)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(12)
          .alignItems(HorizontalAlign.Center)
          .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.1)', offsetY: 2 })

          Column({ space: 8 }) {
            Text(`${this.totalRecipes}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2196F3')

            Text('配方总数')
              .fontSize(14)
              .fontColor(this.getColors().textSecondary)
          }
          .width('48%')
          .padding(24)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(12)
          .alignItems(HorizontalAlign.Center)
          .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.1)', offsetY: 2 })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        // 快速操作
        Column({ space: 12 }) {
          Text('快速操作')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().textPrimary)

          Button('刷新所有数据')
            .width('100%')
            .onClick(() => {
              this.refreshAll();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getColors().cardBackground)
        .borderRadius(12)
      }
      .padding(16)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  StatCard(title: string, value: number, color: string) {
    Column({ space: 8 }) {
      Text(`${value}`)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(title)
        .fontSize(14)
        .fontColor(this.getColors().textSecondary)
    }
    .width('100%')
    .padding(24)
    .backgroundColor(this.getColors().cardBackground)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 4, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.1)', offsetY: 2 })
  }

  @Builder
  UserListView() {
    List({ space: 12 }) {
      ForEach(this.userList, (user: User) => {
        ListItem() {
          Row({ space: 12 }) {
            // 用户头像
            Image(
              user.avatar && user.avatar.length > 0
                ? APIService.getInstance().getFullImageUrl(user.avatar)
                : APIService.getInstance().getFullImageUrl('/uploads/avatars/test.jpg')
            )
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.getColors().divider)

            // 用户信息
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text(user.username)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getColors().textPrimary)

                if (user.role === 'admin') {
                  Text('ADMIN')
                    .fontSize(10)
                    .fontColor(Color.White)
                    .backgroundColor('#FF3B30')
                    .borderRadius(4)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                }
              }

              Text(`ID: ${user.id}`)
                .fontSize(12)
                .fontColor(this.getColors().textTertiary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 删除按钮（非管理员）
            if (user.role !== 'admin') {
              Button('删除')
                .type(ButtonType.Capsule)
                .backgroundColor('#FFEBEE')
                .fontColor('#FF3B30')
                .height(28)
                .fontSize(12)
                .onClick(() => {
                  this.confirmAndDelete(
                    '删除用户',
                    `确定删除用户 ${user.username}?`,
                    () => APIService.getInstance().deleteUser(user.id),
                    () => this.loadUsers()
                  );
                })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(12)
        }
      }, (user: User) => user.id)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  RecipeListView() {
    List({ space: 12 }) {
      ForEach(this.recipeList, (recipe: AdminRecipe) => {
        ListItem() {
          Row({ space: 12 }) {
            // 配方图片
            Image(
              recipe.image && recipe.image.length > 0
                ? APIService.getInstance().getFullImageUrl(recipe.image)
                : $r('app.media.wine')
            )
              .width(60)
              .height(60)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
              .backgroundColor(this.getColors().divider)
              .alt($r('app.media.wine'))
              .onError(() => {
                // 图片加载失败，自动使用 .alt() 设置的默认图片
              })
            
            // 配方信息
            Column({ space: 4 }) {
              Text(recipe.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getColors().textPrimary)

              Text(`创建者: ${recipe.createdBy}`)
                .fontSize(12)
                .fontColor(this.getColors().textSecondary)

              Row({ space: 8 }) {
                Text(`❤️ ${recipe.likeCount || 0}`)
                  .fontSize(12)
                  .fontColor(this.getColors().textTertiary)

                Text(`⭐ ${recipe.favoriteCount || 0}`)
                  .fontSize(12)
                  .fontColor(this.getColors().textTertiary)
              }
              .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 删除按钮
            Button('删除')
              .type(ButtonType.Capsule)
              .backgroundColor('#FFEBEE')
              .fontColor('#FF3B30')
              .height(28)
              .fontSize(12)
              .onClick(() => {
                this.confirmAndDelete(
                  '删除配方',
                  `确定删除配方 "${recipe.name}"?`,
                  () => APIService.getInstance().deleteRecipe(recipe.id),
                  () => this.loadRecipes()
                );
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(12)
        }
      }, (recipe: AdminRecipe) => recipe.id)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  CommentListView() {
    List({ space: 12 }) {
      ForEach(this.commentList, (comment: AdminComment) => {
        ListItem() {
          Column({ space: 8 }) {
            // 评论头部：用户名 + 酒单名 + 时间 + 删除按钮
            Row() {
              Column({ space: 2 }) {
                Text(comment.username)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#007DFF')
                
                if (comment.recipeName) {
                  Text(`酒单: ${comment.recipeName}`)
                    .fontSize(11)
                    .fontColor(this.getColors().textSecondary)
                }
              }
              .alignItems(HorizontalAlign.Start)

              Text(comment.timestamp ? this.formatTimestamp(comment.timestamp) : '')
                .fontSize(11)
                .fontColor(this.getColors().textTertiary)
                .margin({ left: 8 })
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Button('删除')
                .type(ButtonType.Capsule)
                .backgroundColor('#FFEBEE')
                .fontColor('#FF3B30')
                .height(24)
                .fontSize(10)
                .onClick(() => {
                  this.confirmAndDelete(
                    '删除评论',
                    '确定删除这条评论?',
                    () => APIService.getInstance().deleteComment(comment.id),
                    () => this.loadComments()
                  );
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 评论内容
            Text(comment.text)
              .fontSize(14)
              .fontColor(this.getColors().textPrimary)
              .maxLines(5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding(8)
              .backgroundColor(this.getColors().secondaryBackground)
              .borderRadius(8)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.getColors().cardBackground)
          .borderRadius(12)
          .alignItems(HorizontalAlign.Start)
        }
      }, (comment: AdminComment) => comment.id)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // 格式化时间戳
  private formatTimestamp(timestamp: string): string {
    try {
      return timestamp.replace('T', ' ').substring(0, 19);
    } catch (e) {
      return timestamp;
    }
  }
}
