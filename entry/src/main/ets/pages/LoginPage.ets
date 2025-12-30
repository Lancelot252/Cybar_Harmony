// LoginPage.ets - 登录页面
// 对应 Swift 项目中的 LoginView

import APIService from '../services/APIService';
import promptAction from '@ohos.promptAction';
import { ThemeColors, LightTheme, DarkTheme } from '../common/ThemeManager'

@Component
export struct LoginPage {
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  onSuccess?: () => void;
  onCancel?: () => void;

  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme
  }

  private async handleLogin() {
    if (this.username.trim() === '' || this.password.trim() === '') {
      promptAction.showToast({ message: '请输入用户名和密码' });
      return;
    }

    this.isLoading = true;

    try {
      const message = await APIService.getInstance().login(this.username, this.password);

      // 登录成功后重新检查状态
      await APIService.getInstance().checkAuthStatus();

      promptAction.showToast({ message: message });

      // 登录成功,延迟关闭
      setTimeout(() => {
        if (this.onSuccess) {
          this.onSuccess();
        }
      }, 300);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : '登录失败';
      promptAction.showToast({ message: errorMsg });
    } finally {
      this.isLoading = false;
    }
  }

  @State isPrivacyChecked: boolean = false;

  build() {
    Column() {
      // 1. 顶部导航栏 (关闭按钮)
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([this.getColors().primary])
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })

        Blank()

        Text('帮助')
          .fontSize(14)
          .fontColor(this.getColors().textSecondary)
      }
      .width('100%')
        .height(56)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          // 2. 标题区域
          Column({ space: 8 }) {
            Text('登录 Cybar')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().textPrimary)

            Text('探索鸡尾酒的无限可能')
              .fontSize(14)
              .fontColor(this.getColors().textSecondary)
          }
          .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 32, top: 40, bottom: 40 })

          // 3. 登录表单
          Column({ space: 24 }) {
            // 用户名输入框 (下划线风格)
            Column() {
              TextInput({ placeholder: '请输入用户名', text: this.username })
                .width('100%')
                .height(50)
                .backgroundColor(Color.Transparent)
                .fontColor(this.getColors().textPrimary)
                .placeholderColor(this.getColors().textTertiary)
                .borderRadius(0)
                .padding({ left: 0 })
                .onChange((value: string) => {
                  this.username = value;
                })

              Divider()
                .color(this.getColors().divider)
                .strokeWidth(1)
            }
            .width('100%')

            // 密码输入框 (下划线风格)
            Column() {
              TextInput({ placeholder: '请输入密码', text: this.password })
                .width('100%')
                .height(50)
                .type(InputType.Password)
                .backgroundColor(Color.Transparent)
                .fontColor(this.getColors().textPrimary)
                .placeholderColor(this.getColors().textTertiary)
                .borderRadius(0)
                .padding({ left: 0 })
                .onChange((value: string) => {
                  this.password = value;
                })

              Divider()
                .color(this.getColors().divider)
                .strokeWidth(1)
            }
            .width('100%')

            // 忘记密码链接
            Text('忘记密码？')
              .fontSize(12)
              .fontColor('#007DFF')
              .alignSelf(ItemAlign.End)

            // 登录按钮
            Button() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color(Color.White)
                    .margin({ right: 8 })
                }
                Text(this.isLoading ? '登录中...' : '登录')
                  .fontSize(16)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Medium)
              }
            }
            .width('100%')
              .height(48)
              .backgroundColor('#007DFF') // 保持应用主题色
              .type(ButtonType.Capsule) // 胶囊形状
              .shadow({ radius: 8, color: 'rgba(0, 125, 255, 0.3)', offsetY: 4 })
              .margin({ top: 20 })
              .enabled(!this.isLoading)
              .opacity(this.isLoading ? 0.7 : 1.0)
              .onClick(() => {
                if (!this.isPrivacyChecked) {
                  promptAction.showToast({ message: '请先阅读并同意协议' });
                  return;
                }
                this.handleLogin();
              })

            // 隐私协议勾选
            Row({ space: 4 }) {
              Checkbox({ name: 'privacy', group: 'privacy' })
                .select(this.isPrivacyChecked)
                .selectedColor('#007DFF')
                .width(16)
                .height(16)
                .onChange((value: boolean) => {
                  this.isPrivacyChecked = value;
                })

              Text() {
                Span('我已阅读并同意').fontColor(this.getColors().textSecondary)
                Span('《用户协议》').fontColor('#007DFF')
                Span('和').fontColor(this.getColors().textSecondary)
                Span('《隐私政策》').fontColor('#007DFF')
              }
              .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ top: 0 })
          }
          .width('100%')
            .padding({ left: 32, right: 32 })

          // 4. 底部其他登录方式
          Column({ space: 20 }) {
            Row() {
              Divider().layoutWeight(1).color(this.getColors().divider)
              Text('其他登录方式')
                .fontSize(12)
                .fontColor(this.getColors().textTertiary)
                .margin({ left: 12, right: 12 })
              Divider().layoutWeight(1).color(this.getColors().divider)
            }
            .width('100%')
              .padding({ left: 40, right: 40 })

            Row({ space: 40 }) {
              // 微信 (模拟)
              Column({ space: 8 }) {
                Image($r('sys.symbol.person_crop_circle_fill_1')) // 暂用系统图标代替
                  .width(44)
                  .height(44)
                  .fillColor('#09B83E')
                  .backgroundColor(this.getColors().inputBackground)
                  .borderRadius(22)
                  .padding(8)
                Text('微信').fontSize(10).fontColor(this.getColors().textSecondary)
              }

              // QQ (模拟)
              Column({ space: 8 }) {
                Image($r('sys.symbol.person_2_fill')) // 暂用系统图标代替
                  .width(44)
                  .height(44)
                  .fillColor('#12B7F5')
                  .backgroundColor(this.getColors().inputBackground)
                  .borderRadius(22)
                  .padding(8)
                Text('QQ').fontSize(10).fontColor(this.getColors().textSecondary)
              }
            }
          }
          .margin({ top: 80, bottom: 40 })
        }
        .width('100%')
          .constraintSize({ minHeight: '100%' }) // 确保内容撑满
      }
      .layoutWeight(1)
        .scrollBar(BarState.Off)
    }
    .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().background)
  }
}
