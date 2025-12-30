// RegisterPage.ets - 注册页面
// 对应 Swift 项目中的 RegisterView

import APIService from '../services/APIService';
import promptAction from '@ohos.promptAction';
import { ThemeColors, LightTheme, DarkTheme } from '../common/ThemeManager'

@Component
export struct RegisterPage {
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State isLoading: boolean = false;
  onSuccess?: () => void;
  onCancel?: () => void;

  private getColors(): ThemeColors {
    return this.isDarkMode ? DarkTheme : LightTheme
  }

  // 检查表单是否有效
  private checkFormValid(): boolean {
    const usernameValid = this.username.trim().length > 0;
    const passwordValid = this.password.trim().length > 0;
    const confirmValid = this.confirmPassword.trim().length > 0;
    const passwordMatch = this.password === this.confirmPassword;

    console.info(`[Register] 验证: username=${usernameValid}, password=${passwordValid}, confirm=${confirmValid}, match=${passwordMatch}`);

    return usernameValid && passwordValid && confirmValid && passwordMatch;
  }

  private async handleRegister() {
    // 验证表单
    if (this.username.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名' });
      return;
    }
    if (this.password.trim().length === 0) {
      promptAction.showToast({ message: '请输入密码' });
      return;
    }
    if (this.confirmPassword.trim().length === 0) {
      promptAction.showToast({ message: '请确认密码' });
      return;
    }
    if (this.password !== this.confirmPassword) {
      promptAction.showToast({ message: '两次密码不一致' });
      return;
    }

    this.isLoading = true;

    try {
      const message = await APIService.getInstance().register(this.username, this.password);

      // 注册成功后自动登录
      await APIService.getInstance().login(this.username, this.password);

      // 重新检查状态
      await APIService.getInstance().checkAuthStatus();

      promptAction.showToast({ message: '注册成功,已自动登录' });

      // 注册成功,延迟关闭
      setTimeout(() => {
        if (this.onSuccess) {
          this.onSuccess();
        }
      }, 300);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : '注册失败';
      promptAction.showToast({ message: errorMsg });
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 1. 顶部导航栏 (关闭按钮)
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([this.getColors().textPrimary])
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
            Text('加入 Cybar')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().textPrimary)

            Text('创建您的专属账户')
              .fontSize(14)
              .fontColor(this.getColors().textSecondary)
          }
          .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 32, top: 40, bottom: 40 })

          // 3. 注册表单
          Column({ space: 24 }) {
            // 用户名输入框
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

            // 密码输入框
            Column() {
              TextInput({ placeholder: '设置密码', text: this.password })
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

            // 确认密码输入框
            Column() {
              TextInput({ placeholder: '确认密码', text: this.confirmPassword })
                .width('100%')
                .height(50)
                .type(InputType.Password)
                .backgroundColor(Color.Transparent)
                .fontColor(this.getColors().textPrimary)
                .placeholderColor(this.getColors().textTertiary)
                .borderRadius(0)
                .padding({ left: 0 })
                .onChange((value: string) => {
                  this.confirmPassword = value;
                })

              Divider()
                .color(this.getColors().divider)
                .strokeWidth(1)
            }
            .width('100%')

            // 注册按钮
            Button() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color(Color.White)
                    .margin({ right: 8 })
                }
                Text(this.isLoading ? '注册中...' : '注册')
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
                this.handleRegister();
              })

          }
          .width('100%')
            .padding({ left: 32, right: 32 })
        }
        .width('100%')
          .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
        .scrollBar(BarState.Off)
    }
    .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().background)
  }

}
