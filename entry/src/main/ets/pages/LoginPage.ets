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
  
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button({ type: ButtonType.Normal }) {
          Text('取消')
            .fontSize(16)
            .fontColor(this.getColors().primary)
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel();
          }
        })
        
        Blank()
        
        Text('登录')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().textPrimary)
        
        Blank()
        
        // 占位,保持标题居中
        Text('   ')
          .width(50)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      
      Scroll() {
        Column() {
          // Logo和标题
          Column({ space: 16 }) {
            Image($r('sys.symbol.drop'))
              .width(60)
              .height(60)
              .fillColor(this.getColors().primary)
            
            Text('欢迎回来')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().textPrimary)
            
            Text('登录您的账户')
              .fontSize(14)
              .fontColor(this.getColors().textSecondary)
          }
          .margin({ top: 40, bottom: 60 })
          
          // 登录表单
          Column({ space: 16 }) {
            // 用户名
            Column({ space: 8 }) {
              Text('用户名')
                .fontSize(12)
                .fontColor(this.getColors().textSecondary)
                .alignSelf(ItemAlign.Start)
              
              TextInput({ placeholder: '请输入用户名', text: this.username })
                .width('100%')
                .height(48)
                .backgroundColor(this.getColors().inputBackground)
                .fontColor(this.getColors().textPrimary)
                .placeholderColor(this.getColors().textTertiary)
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.username = value;
                })
            }
            .width('100%')
            
            // 密码
            Column({ space: 8 }) {
              Text('密码')
                .fontSize(12)
                .fontColor(this.getColors().textSecondary)
                .alignSelf(ItemAlign.Start)
              
              TextInput({ placeholder: '请输入密码', text: this.password })
                .width('100%')
                .height(48)
                .type(InputType.Password)
                .backgroundColor(this.getColors().inputBackground)
                .fontColor(this.getColors().textPrimary)
                .placeholderColor(this.getColors().textTertiary)
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.password = value;
                })
            }
            .width('100%')
            
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
            .backgroundColor(this.getColors().primary)
            .borderRadius(12)
            .margin({ top: 8 })
            .enabled(!this.isLoading && this.username.trim() !== '' && this.password.trim() !== '')
            .opacity((!this.isLoading && this.username.trim() !== '' && this.password.trim() !== '') ? 1.0 : 0.6)
            .onClick(() => {
              this.handleLogin();
            })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().background)
  }
}
