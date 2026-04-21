非root用户可以使用Xposed JustTrustMe模块来抓包，支持安卓14，我测试大部分都可以抓到。

### 第一步 下载伏羲 伏羲可以使应用加载本机已安装的Xposed模块

官网：https://www.die.lu/
下载 svxp64_xx.apk
Github下载: https://github.com/Katana-Official/SPatch-Update/releases
网盘下载(提取码2035): https://url38.ctfile.com/d/15037138-28988502-8fce96

安装完应用就是伏羲x64

![输入图片说明](https://foruda.gitee.com/images/1701624799399669180/d50b51a7_1073801.png "屏幕截图")


### 第二步 安装JustTrustMe模块 必须使用伏羲从文件管理器安装
JustTrustMe是一个禁用SSL证书检查的Xposed模块

Giuhub下载: https://github.com/Fuzion24/JustTrustMe/releases
网盘下载(提取码8902): https://url37.ctfile.com/f/50805637-984778183-a2b7a3?p=8902

打开伏羲应用，点击右下角菜单栏 选择从文件管理器安装，从文件夹选择下载好的JustTrustMe.apk
![输入图片说明](https://foruda.gitee.com/images/1701656562516770260/bbd844b2_1073801.png "屏幕截图")

安装成功后可以从模块作用管理器看到
![输入图片说明](https://foruda.gitee.com/images/1701625567175643670/79162358_1073801.png "屏幕截图")

### 第三步 克隆要抓包的应用
从伏羲应用点击右下角菜单栏，选择添加(安装)克隆软件
选择要抓包的软件，点击右下角1，选择克隆数量完成。

![
](https://foruda.gitee.com/images/1701625701181960615/c0d5d643_1073801.png "屏幕截图")

### 最终 开始抓包
打开抓包软件ProxyPin，然后从伏羲打开刚才克隆的应用，就可以开始抓包了，我测试大部分都可以抓，如有有些域名全部都是SSL握手失败，为了不影响应用使用，可以在ProxyPin将域名加入域名黑名单

![输入图片说明](https://foruda.gitee.com/images/1701627522386866284/98d67136_1073801.png "屏幕截图")

