// RegisterPage.ets - 注册页面
// 对应 Swift 项目中的 RegisterView

import APIService from '../services/APIService';
import promptAction from '@ohos.promptAction';

@Component
export struct RegisterPage {
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State isLoading: boolean = false;
  onSuccess?: () => void;
  onCancel?: () => void;
  
  private get isFormValid(): boolean {
    return this.username.trim() !== '' &&
           this.password.trim() !== '' &&
           this.confirmPassword.trim() !== '' &&
           this.password === this.confirmPassword;
  }
  
  private async handleRegister() {
    if (!this.isFormValid) {
      promptAction.showToast({ message: '请完整填写表单' });
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
      // 顶部导航栏
      Row() {
        Button({ type: ButtonType.Normal }) {
          Text('取消')
            .fontSize(16)
            .fontColor('#007DFF')
        }
        .backgroundColor('#00000000')
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel();
          }
        })
        
        Blank()
        
        Text('注册')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        
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
              .fillColor('#34C759')
            
            Text('加入我们')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
            
            Text('创建您的账户')
              .fontSize(14)
              .fontColor('#999999')
          }
          .margin({ top: 40, bottom: 60 })
          
          // 注册表单
          Column({ space: 16 }) {
            // 用户名
            Column({ space: 8 }) {
              Text('用户名')
                .fontSize(12)
                .fontColor('#999999')
                .alignSelf(ItemAlign.Start)
              
              TextInput({ placeholder: '请输入用户名', text: this.username })
                .width('100%')
                .height(48)
                .backgroundColor('#F5F5F5')
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
                .fontColor('#999999')
                .alignSelf(ItemAlign.Start)
              
              TextInput({ placeholder: '请输入密码', text: this.password })
                .width('100%')
                .height(48)
                .type(InputType.Password)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.password = value;
                })
            }
            .width('100%')
            
            // 确认密码
            Column({ space: 8 }) {
              Text('确认密码')
                .fontSize(12)
                .fontColor('#999999')
                .alignSelf(ItemAlign.Start)
              
              TextInput({ placeholder: '请再次输入密码', text: this.confirmPassword })
                .width('100%')
                .height(48)
                .type(InputType.Password)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.confirmPassword = value;
                })
            }
            .width('100%')
            
            // 密码不匹配提示
            if (this.password !== '' && this.confirmPassword !== '' && this.password !== this.confirmPassword) {
              Text('两次输入的密码不一致')
                .fontSize(12)
                .fontColor('#FF3B30')
                .alignSelf(ItemAlign.Start)
            }
            
            // 注册按钮
            Button() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color('#FFFFFF')
                    .margin({ right: 8 })
                }
                Text(this.isLoading ? '注册中...' : '注册')
                  .fontSize(16)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Medium)
              }
            }
            .width('100%')
            .height(48)
            .backgroundColor('#34C759')
            .borderRadius(12)
            .margin({ top: 8 })
            .enabled(!this.isLoading && this.isFormValid)
            .opacity((!this.isLoading && this.isFormValid) ? 1.0 : 0.6)
            .onClick(() => {
              this.handleRegister();
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
    .backgroundColor('#FFFFFF')
  }
}
