::这是一个主脚本示例,请按照此示例中的启动过程完成脚本的启动.

::常规准备,请勿改动
@ECHO OFF
chcp 936>nul
cd /d %~dp0
if exist bin (cd bin) else (ECHO.找不到bin. 请检查工具是否完全解压, 脚本位置是否正确. & goto FATAL)

::加载配置,如果有自定义的配置文件也可以加在下面
if exist conf\fixed.bat (call conf\fixed) else (ECHO.找不到conf\fixed.bat & goto FATAL)
if exist conf\user.bat call conf\user
if not "%product%"=="" (if exist conf\dev-%product%.bat call conf\dev-%product%.bat)

::加载主题,请勿改动
if "%framework_theme%"=="" set framework_theme=default
call framework theme %framework_theme%
COLOR %c_i%

::自定义窗口大小,可以按照需要改动
TITLE 工具启动中...
mode con cols=71

::检查和获取管理员权限,若不涉及需要管理员权限的程序可以去除
if not exist tool\Win\gap.exe ECHO.找不到gap.exe. 请检查工具是否完全解压, 脚本位置是否正确. & goto FATAL
tool\Win\gap.exe %0 || EXIT

::启动准备和检查,请勿改动
call framework startpre
::call framework startpre skiptoolchk

::完成启动.请在下面编写你的脚本
TITLE [未选择机型] 中兴家族工具箱 %prog_ver% by酷安@某贼 [永久免费 禁止倒卖]
CLS
if "%product%"=="" goto SELDEV
if not exist conf\dev-%product%.bat goto SELDEV
goto MENU



:MENU
TITLE [%model%] 中兴家族工具箱 %prog_ver% by酷安@某贼 [永久免费 禁止倒卖]
if not exist res\%product%\bak md res\%product%\bak
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.中兴家族工具箱 %prog_ver% by酷安@某贼 [永久免费 禁止倒卖]
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.
ECHOC {%c_w%}[%model%]{%c_i%} %cpu%{%c_i%}{\n}
ECHOC {%c_we%}若机型不正确请先使用"选择机型"功能{%c_i%}{\n}
ECHO.
ECHO.
ECHO.^< 警告: Root等刷入非官方固件的操作均以解锁BL为基础, 否则会变砖! ^>
ECHO.
ECHO.0.解锁BL           000.上锁BL(不建议)
ECHO.1.获取Root         111.Root不开机恢复
ECHO.2.9008线刷完整包
ECHO.3.刷入Recovery(TWRP)
ECHO.4.备份全分区(备份字库)
ECHO.
::ECHO.10.努比亚临时解锁  11.9008发送引导
::ECHO.11.9008发送引导    
ECHO.14.adb投屏
ECHO.12.刷入任意分区    13.回读任意分区
::ECHO.         15.临时进入全功能Fastboot
ECHO.16.查看, 设置槽位  17.备份恢复QCN
ECHO.18.骁龙8E5免解BL+保指纹  19.清空efisp分区(去除开机小字)
ECHO.20.清空frp分区     21.一键改定制
ECHO.
ECHO.A.打开备份文件夹
ECHO.B.选择机型
ECHO.C.检查更新 (密码: ebxn)
ECHO.D.更换主题
ECHO.
ECHO.E.中兴努比亚红魔交流反馈群
ECHO.F.萤火虫刷机资源站 (下载9008包, TWRP等刷机资源)
ECHO.G.关于BFF
ECHO.
call input choice [0][000][1][111][2][3][4][12][13][14][16][17][18][19][20][21][A][B][C][D]#[E][F][G]
if "%choice%"=="0" goto UNLOCKBL
if "%choice%"=="000" goto LOCKBL
if "%choice%"=="1" goto ROOT
if "%choice%"=="111" goto ROOT-REC
if "%choice%"=="2" goto EDLFLASHFULL
if "%choice%"=="3" goto FLASHREC
if "%choice%"=="4" goto BAKALL
if "%choice%"=="10" goto NUBIAUNLOCK
if "%choice%"=="11" goto EDLSENDFH
if "%choice%"=="12" goto WRITEPAR
if "%choice%"=="13" goto READPAR
if "%choice%"=="14" call scrcpy 中兴家族工具箱-adb投屏
if "%choice%"=="15" goto ENTERDBGFB
if "%choice%"=="16" goto SLOT
if "%choice%"=="17" goto QCN
if "%choice%"=="18" goto 8E5CUSTOMIZEDBL
if "%choice%"=="19" goto CLEANEFISP
if "%choice%"=="20" goto CLEANFRP
if "%choice%"=="21" goto CONVERTEDITION
if "%choice%"=="A" call open folder res\%product%\bak
if "%choice%"=="B" goto SELDEV
if "%choice%"=="C" call open common https://syxz.lanzoue.com/b01g0i33c
if "%choice%"=="D" goto THEME
if "%choice%"=="E" start "" "https://yhfx.jwznb.com/share?key=BBmdd7wE9CNv&ts=1707895931 "
if "%choice%"=="F" call open common https://www.yhcres.top/
if "%choice%"=="G" call open common https://gitee.com/mouzei/bff
goto MENU




:CONVERTEDITION
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.一键改定制
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.-功能说明:
ECHO. 本功能可将普通版设备改为定制版, 从而可以使用定制主题.
ECHO. 不需要解锁BL. 不改变设备SN.
ECHOC {%c_i%} 本功能可能需要{%c_e%}清除数据{%c_i%}, 请备份好个人数据再操作.{%c_i%}{\n}
ECHO. 当前主题可能会被覆盖, 如有需要请做好备份.
ECHO. 定制主题依赖官方系统, 刷入移植或类原生包无法显示定制主题.
ECHO. 过早版本的系统 (例如出厂包或媒体包) 可能不含定制主题, 从而无法显示.
ECHO. 本功能仅供个人学习研究, 不得牟利或用于非法用途, 否则后果自负.
ECHO.
if not exist res\%product%\edition.csv ECHOC {%c_e%}%model%暂不支持此功能. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU
if "%product%"=="NX733J" ECHOC {%c_w%}注意: {%c_i%}努比亚Z70Ultra普通版改星空版, 除了需要在此页面操作, 还需要刷入星空版专包. 请访问yhcres.top下载带有NX736J标识的9008线刷救砖包刷入.{%c_i%}{\n}& ECHO.
ECHO.当前选定设备: %model% & ECHO.请选择想要的版本: & ECHO.
type res\%product%\edition.csv | find /v "[edition_str]" | find "[" | find /N "]" 1>%tmpdir%\tmp.txt
for /f "tokens=1,3 delims=[]," %%a in (%tmpdir%\tmp.txt) do (ECHO.[%%a] %%b)
ECHO.[A] 返回主菜单
ECHO.& call input choice
if "%choice%"=="A" goto MENU
if "%choice%"=="" goto CONVERTEDITION
find "[%choice%][" "%tmpdir%\tmp.txt" 1>nul 2>nul || goto CONVERTEDITION
ECHO.加载配置中...
for /f "tokens=2 delims=[]," %%a in ('type %tmpdir%\tmp.txt ^| find "[%choice%]["') do set edition_str=%%a
call ztetoolbox confeditionpre
ECHOC {%c_h%}请进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.备份当前ztecfg...
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
call read qcedl ztecfg res\%product%\bak\ztecfg_%baktime%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.文件已备份到bin\res\%product%\bak\ztecfg_%baktime%.img.
ECHO.检查ztecfg...
busybox.exe dd if=res\%product%\bak\ztecfg_%baktime%.img bs=1 skip=4320 count=32 2>nul | busybox.exe tr -d \000 1>%tmpdir%\tmp.txt || goto FATAL
set edition_str_read=
for /f %%a in (%tmpdir%\tmp.txt) do set edition_str_read=%%a
find "[%edition_str_read%]" "res\%product%\edition.csv" 1>nul 2>nul || call :convertedition-unknownedition
ECHO.修改ztecfg...
copy /Y res\%product%\bak\ztecfg_%baktime%.img %tmpdir%\ztecfg_new.img 1>>%logfile% 2>&1 || goto FATAL
HexTool.exe %tmpdir%\ztecfg_new.img 4320 32 %edition_hex% 1>>%logfile% 2>&1 || goto FATAL
ECHO.刷入ztecfg... & call write qcedl ztecfg %tmpdir%\ztecfg_new.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
ECHOC {%c_s%}完成. {%c_i%}如果不开机, 请手动进入Recovery恢复出厂再试. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU
:convertedition-unknownedition
ECHOC {%c_e%}未知版本代码: %edition_str_read%{%c_i%}{\n}
ECHO.继续可能有风险. 建议现在停止操作, 截图此页面, 并加群联系开发者说明情况. 手机长按电源键即可正常开机.
ECHOC {%c_h%}仍要继续, 请按任意键...{%c_i%}{\n}& pause>nul
goto :eof


:CLEANFRP
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.清空frp分区
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.-功能说明:
ECHO. 用于解决因为刷机前未退出谷歌账号, 导致系统无法安装软件的问题(尚需测试)
ECHO.
ECHOC {%c_h%}了解以上信息, 请按任意键开始...{%c_i%}{\n}& pause>nul
ECHOC {%c_h%}请进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.清空frp... & call write qcedl frp tool\Other\frp_empty.img %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.重启... & call reboot qcedl system
ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:CLEANEFISP
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.清空efisp分区 (去除开机小字)
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
if not "%blplan%"=="efisp" ECHO.%model%不适用于此功能. 按任意键返回... & pause>nul & goto MENU
ECHO. [%model%]
ECHO.
ECHO.-功能说明:
ECHO. 开机第一屏出现小字就是efisp分区中程序运行的表现, 说明efisp内有程序
ECHO. 由于多数9008包不刷入efisp分区, 故单独加入此功能, 以便使用
ECHO. efisp分区原本就是空分区, 无任何数据, 直接清空即为恢复原状
ECHO. 使用命令擦除可能效果不佳, 本功能通过刷入空分区文件, 可实现完全清空
ECHO. 除免解外, 正常解锁上锁操作完成后, 均无需保留efisp中的程序, 建议清空
ECHO. 清空指清空分区内容, 并非删除分区本身
ECHO. 
ECHOC {%c_h%}了解以上信息, 请按任意键开始...{%c_i%}{\n}& pause>nul
ECHOC {%c_h%}请进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.清空efisp... & call write qcedl efisp tool\Other\8e5gbl\efisp_empty.img %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.重启... & call reboot qcedl system
ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:8E5CUSTOMIZEDBL
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.骁龙8E5免解BL+保指纹
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
if not "%blplan%"=="efisp" ECHO.%model%不适用于此功能. 按任意键返回... & pause>nul & goto MENU
ECHO. [%model%]
ECHO.
ECHO.-注意事项:
ECHO. 刷入特制的引导加载程序, 从efisp而不是官方abl引导启动, 从而实现免解锁修改系统
ECHO. 基于以上原理, 使用本功能后, 如果清除efisp, 功能会失效
ECHO. 未解锁BL的, 使用后可上锁状态直接刷第三方 (包括Root等), 可通过9008刷分区
ECHO. 已解锁BL的, 使用后可使系统指纹可用
ECHO. 使用本功能不会清除数据, 但仍建议重要数据做好备份
ECHO. 由于可能有部分校验未去除, 免解刷第三方不保证一定开机
ECHO. 若当前系统已修复efisp漏洞, 本功能将无效
ECHO. 如需清除免解程序, 请使用工具箱"清空efisp分区"功能
ECHO.
ECHOC {%c_h%}了解以上信息, 请按任意键开始...{%c_i%}{\n}& pause>nul
ECHO.
ECHOC {%c_h%}请进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.刷入免解程序... & call write qcedl efisp tool\Other\8e5gbl\gbl_superfastboot.efi %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.重启... & call reboot qcedl system
ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:QCN
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.备份, 恢复QCN
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]
ECHO.
ECHO.QCN包含设备的基带, 串号等信息. 本功能等同于QFIL的QCN相关功能. 本功能需要Root权限.
ECHO.
ECHO.1.备份QCN   2.恢复QCN   A.返回主菜单
ECHO.
call input choice [1][2][A]
ECHO.
if "%choice%"=="A" goto MENU
if "%choice%"=="1" goto QCN-READ
if "%choice%"=="2" goto QCN-WRITE
EXIT
:QCN-READ
ECHOC {%c_h%}请开机并开启USB调试...{%c_i%}{\n}& call chkdev system rechk 1
ECHO.开启基带调试端口... & call reboot system qcdiag rechk 1
for /f %%a in ('gettime.exe') do set baktime=%%a
ECHO.备份QCN到 bin\res\%product%\bak\qcnbak_%baktime%.qcn . 耗时较长, 请耐心等待... & call read qcdiag %chkdev__port__qcdiag% res\%product%\bak\qcnbak_%baktime%.qcn
goto QCN-DONE
:QCN-WRITE
ECHOC {%c_h%}请选择要恢复的QCN文件...{%c_i%}{\n}& call sel file s %framework_workspace%\res\%product%\bak [qcn]
ECHOC {%c_h%}请开机并开启USB调试...{%c_i%}{\n}& call chkdev system rechk 1
ECHO.开启基带调试端口... & call reboot system qcdiag rechk 1
ECHO.恢复QCN. 耗时较长, 请耐心等待... & call write qcdiag %chkdev__port__qcdiag% %sel__file_path%
goto QCN-DONE
:QCN-DONE
ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:BAKALL
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.备份全分区(备份字库)
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]
ECHO.
ECHO.-注意事项:
ECHO. 本功能会备份设备所有分区(userdata和last_parti除外)和分区表
ECHO. 备份中不包含用户数据
ECHO. 备份后自动生成xml, 可用工具箱"9008刷入完整包"功能刷入
ECHO. 全分区备份中包含串号, 传感器等特殊分区, 故只能用于原设备, 不可混用, 否则后果自负
ECHO. 及时备份全分区可以最大程度地预防格机
ECHO.
ECHOC {%c_h%}了解以上信息, 请按任意键开始...{%c_i%}{\n}& pause>nul
ECHO.
ECHOC {%c_h%}请选择保存位置...{%c_i%}{\n}& call sel folder s %framework_workspace%\..
ECHOC {%c_h%}请进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
md %sel__folder_path%\ZTEToolBoxParBak_%baktime% 1>nul || ECHOC {%c_e%}创建%sel__folder_path%\ZTEToolBoxParBak_%baktime%失败{%c_i%}{\n}&& goto FATAL
start framework logviewer start %logfile%
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.正在9008回读全分区... & call ztetoolbox edlreadall %chkdev__port__qcedl% %sel__folder_path%\ZTEToolBoxParBak_%baktime%
ECHO.9008回读全分区完成. 重启手机... & call reboot qcedl system
call framework logviewer end
ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:SLOT
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.查看, 设置槽位
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]
ECHO.
if "%parlayout%"=="aonly" ECHO.%model%无需此功能. 按任意键返回... & pause>nul & goto MENU
set slot__a_unbootable=& set slot__b_unbootable=
ECHOC {%c_h%}请将设备进入系统, Recovery, Fastboot或9008模式...{%c_i%}{\n}& call chkdev all
::if not "%chkdev__mode%"=="system" (if not "%chkdev__mode%"=="recovery" (if not "%chkdev__mode%"=="fastboot" ECHOC {%c_e%}模式错误, 请进入系统, Recovery或Fastboot模式. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 模式错误:%chkdev__mode%.应进入系统或Recovery或Fastboot模式& pause>nul & ECHO.重试... & goto SLOT))
if "%chkdev__mode%"=="qcedl" ECHO.发送引导... & call write qcedlsendfh %chkdev__port% %framework_workspace%\res\%product%\devprg %storagetype%
ECHO.检查槽位... & call slot %chkdev__mode% chk
ECHO.
    ECHOC {%c_i%}当前槽位: %slot__cur%{%c_i%}
    if "%slot__cur_unbootable%"=="yes" ECHOC {%c_e%}(不可启动){%c_i%}
    ECHOC {%c_i%}   {%c_i%}
    ECHOC {%c_i%}另一槽位: %slot__cur_oth%{%c_i%}
    if "%slot__cur_unbootable%"=="yes" ECHOC {%c_e%}(不可启动){%c_i%}
    ECHOC {%c_i%}{\n}
ECHO.
ECHO.A.激活 a 槽位   B.激活 b 槽位   C.返回主菜单
ECHO.
call input choice [A][B]#[C]
if "%choice%"=="A" set target=a
if "%choice%"=="B" set target=b
if "%choice%"=="C" goto MENU
ECHO.正在设置槽位为 %target% ... & call slot %chkdev__mode% set %target%
if "%chkdev__mode%"=="qcedl" call reboot qcedl qcedl
goto SLOT


:FLASHREC
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.刷入Recovery(TWRP)
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]  分区类型: %parlayout%
ECHO.
ECHO.-注意事项:
ECHO. 使用本功能必须解锁BL锁
if not "%parlayout%"=="ab" ECHO. 官方boot开机时可能自动将recovery恢复官方. 提前Root可以避免此问题.
ECHO.
ECHO.1.刷入   2.Fastboot临时启动   3.将TWRP注入boot文件(用于无recovery设备)
ECHO.A.下载TWRP   B.返回主菜单
ECHO.
call input choice #[1][2][3][A][B]
if "%choice%"=="1" set func=flash
if "%choice%"=="2" set func=boot
if "%choice%"=="3" set func=recinst
if "%choice%"=="A" call open common https://yhcres.top/ & call open common https://twrp.me/Devices/ & goto FLASHREC
if "%choice%"=="B" goto MENU
ECHO.
goto FLASHREC-%func%
:FLASHREC-RECINST
if not "%parlayout%"=="ab" ECHO.%model% 无需此功能. 按任意键返回... & pause>nul & goto FLASHREC
ECHOC {%c_h%}请选择TWRP镜像文件...{%c_i%}{\n}& call sel file s %framework_workspace%\.. [img]
set recpath=%sel__file_path%
ECHOC {%c_h%}请选择boot镜像文件...{%c_i%}{\n}& call sel file s %framework_workspace%\.. [img]
set bootpath=%sel__file_path%
ECHOC {%c_h%}请选择新boot文件保存位置...{%c_i%}{\n}& call sel folder s %framework_workspace%\..
ECHO.注入recovery... & call imgkit recinst %bootpath% %sel__folder_path%\boot_new.img %recpath%
ECHO.新boot位于%sel__folder_path%\boot_new.img.
goto FLASHREC-DONE
:FLASHREC-BOOT
ECHOC {%c_h%}请选择TWRP镜像文件...{%c_i%}{\n}& call sel file s %framework_workspace%\.. [img]
ECHOC {%c_h%}请进入Fastboot...{%c_i%}{\n}& call chkdev fastboot
ECHO.临时启动... & call write fastbootboot %sel__file_path%
goto FLASHREC-DONE
:FLASHREC-FLASH
ECHOC {%c_h%}请选择TWRP镜像文件...{%c_i%}{\n}& call sel file s %framework_workspace%\.. [img]
ECHOC {%c_h%}请开机并开启USB调试...{%c_i%}{\n}& call chkdev system rechk 1
if not "%parlayout%"=="aonly" ECHO.读取槽位信息... & call slot system chk
ECHO.当前槽位: %slot__cur%
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto FLASHREC-FLASH-%parlayout%
:FLASHREC-FLASH-AONLY
ECHO.备份当前recovery...
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
call read qcedl recovery res\%product%\bak\recovery_%baktime%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.文件已备份到bin\res\%product%\bak\recovery_%baktime%.img.
ECHO.刷入recovery... & call write qcedl recovery %sel__file_path%
goto FLASHREC-FLASH-DONE
:FLASHREC-FLASH-AB_REC
ECHO.备份当前recovery_%slot__cur%...
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
call read qcedl recovery_%slot__cur% res\%product%\bak\recovery_%slot__cur%_%baktime%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.文件已备份到bin\res\%product%\bak\recovery_%slot__cur%_%baktime%.img.
ECHO.刷入recovery_%slot__cur%... & call write qcedl recovery_%slot__cur% %sel__file_path%
goto FLASHREC-FLASH-DONE
:FLASHREC-FLASH-AB
ECHO.备份当前boot_%slot__cur%...
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
call read qcedl boot_%slot__cur% res\%product%\bak\boot_%slot__cur%_%baktime%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.文件已备份到bin\res\%product%\bak\boot_%slot__cur%_%baktime%.img.
ECHO.注入recovery... & call imgkit recinst %framework_workspace%\res\%product%\bak\boot_%slot__cur%_%baktime%.img %tmpdir%\boot_rec.img %sel__file_path% noprompt
ECHO.刷入boot_%slot__cur%... & call write qcedl boot_%slot__cur% %tmpdir%\boot_rec.img
goto FLASHREC-FLASH-DONE
:FLASHREC-FLASH-DONE
ECHO.
ECHO.1.重启到Recovery   2.不重启
call input choice #[1][2]
if "%choice%"=="1" ECHO.重启到Recovery... & call reboot qcedl recovery
goto FLASHREC-DONE
:FLASHREC-DONE
ECHO. & ECHOC {%c_s%}完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto FLASHREC


:NUBIAUNLOCK
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.努比亚临时解锁
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
if not "%product:~0,2%"=="NX" ECHO.%model% 无需此功能. 按任意键返回... & pause>nul & goto MENU
ECHOC {%c_h%}请进入Fastboot...{%c_i%}{\n}& call chkdev fastboot
ECHO.fastboot.exe oem nubia_unlock NUBIA_%product% & ECHO.
fastboot.exe oem nubia_unlock NUBIA_%product%
ECHO. & ECHO.完成. 按任意键返回... & pause>nul & goto MENU


:READPAR
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.回读任意分区
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.可在系统(需Root), TWRP, 9008任一模式使用
ECHO.输入exit返回主菜单
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHOC {%c_h%}请选择回读文件保存位置...{%c_i%}{\n}& call sel folder s %framework_workspace%\..
ECHO.
:READPAR-1
ECHOC {%c_i%}=--------------------------------------------------------------------={%c_i%}{\n}
if not "%parname%"=="" ECHO.上次: %parname%
ECHOC {%c_h%}分区名: {%c_i%}& set /p parname=
if "%parname%"=="" goto READPAR-1
if "%parname%"=="exit" goto MENU
:READPAR-2
call chkdev all
ECHO.正在回读... & call read %chkdev__mode% %parname% %sel__folder_path%\%parname%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%chkdev__mode%"=="qcedl" call reboot qcedl qcedl
ECHOC {%c_s%}回读完成{%c_i%}{\n}& goto READPAR-1


:WRITEPAR
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.刷入任意分区
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.可在系统(需Root), TWRP, Fastboot, 9008任一模式使用
ECHO.输入exit返回主菜单
ECHO.
:WRITEPAR-1
ECHOC {%c_i%}=--------------------------------------------------------------------={%c_i%}{\n}
if not "%parname%"=="" ECHO.上次: %parname%
ECHOC {%c_h%}分区名: {%c_i%}& set /p parname=
if "%parname%"=="" goto WRITEPAR-1
if "%parname%"=="exit" goto MENU
if "%imgfolder%"=="" set imgfolder=%framework_workspace%\..
ECHOC {%c_h%}请选择 %parname% 分区文件...{%c_i%}{\n}& call sel file s %imgfolder%
set imgfolder=%sel__file_folder%
:WRITEPAR-2
call chkdev all
ECHO.正在刷入... & call write %chkdev__mode% %parname% %sel__file_path% %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%chkdev__mode%"=="qcedl" call reboot qcedl qcedl
ECHOC {%c_s%}刷入完成{%c_i%}{\n}& goto WRITEPAR-1


:EDLFLASHFULL
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.9008线刷完整包
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]  分区类型: %parlayout%   存储类型: %storagetype%
ECHO.
if not exist %framework_workspace%\res\%product%\devprg\prog_firehose_ddr.elf ECHO.提示: 本功能已停止维护. 推荐使用更完善的[刷机匣]图形化工具进行9008刷机救砖. & ECHO.下载地址: gitee.com/geekflashtool & ECHO.
ECHO.-注意事项
ECHO. 本功能等同于QFIL的9008功能
ECHO. 9008包需要解压使用
ECHO. 刷机前请备份设备内所有个人数据
ECHO. 刷机前建议关闭查找设备, 删除指纹, 删除锁屏密码, 退出账号
ECHO. 官方9008包若刷机失败, 请尝试删除官方包内的userdata.img, 重新打开工具再试
ECHO. 如果刷机后不开机, 请尝试恢复出厂
ECHO.
ECHOC {%c_h%}按任意键开始...{%c_i%}{\n}& pause>nul
ECHO.
set alreadypreedl=n
:EDLFLASHFULL-1
ECHOC {%c_h%}请选择9008包分区镜像和xml所在文件夹...{%c_i%}{\n}& call sel folder s %framework_workspace%\..
if "%alreadypreedl%"=="y" goto EDLFLASHFULL-3
set fhpath=%framework_workspace%\res\%product%\devprg
if not exist %framework_workspace%\res\%product%\devprg ECHOC {%c_h%}请选择引导文件...{%c_i%}{\n}& call sel file s %sel__folder_path% [elf][mbn]
if not exist %framework_workspace%\res\%product%\devprg set fhpath=%sel__file_path%
ECHOC {%c_h%}请进入9008. 如果上次刷机失败, 请关闭脚本, 重新进入9008, 再重新开始刷机...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %fhpath% %storagetype%
set alreadypreedl=y
:EDLFLASHFULL-3
ECHO.检查文件...
goto EDLFLASHFULL-%storagetype%
:EDLFLASHFULL-UFS
    if exist %sel__folder_path%\rawprogram0.xml (set xmls=rawprogram0.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch0.xml set xmls=%xmls%/patch0.xml
    if exist %sel__folder_path%\rawprogram1.xml (set xmls=%xmls%/rawprogram1.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch1.xml set xmls=%xmls%/patch1.xml
    if exist %sel__folder_path%\rawprogram2.xml (set xmls=%xmls%/rawprogram2.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch2.xml set xmls=%xmls%/patch2.xml
    if exist %sel__folder_path%\rawprogram3.xml (set xmls=%xmls%/rawprogram3.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch3.xml set xmls=%xmls%/patch3.xml
    if exist %sel__folder_path%\rawprogram4.xml (set xmls=%xmls%/rawprogram4.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch4.xml set xmls=%xmls%/patch4.xml
    if exist %sel__folder_path%\rawprogram5.xml (set xmls=%xmls%/rawprogram5.xml) else (goto EDLFLASHFULL-FILENOTFOUND)
    if exist %sel__folder_path%\patch5.xml set xmls=%xmls%/patch5.xml
goto EDLFLASHFULL-2
:EDLFLASHFULL-EMMC
    if not exist %sel__folder_path%\rawprogram0.xml goto EDLFLASHFULL-FILENOTFOUND
    set xmls=rawprogram0.xml
    if exist %sel__folder_path%\patch0.xml set xmls=%xmls%/patch0.xml
goto EDLFLASHFULL-2
:EDLFLASHFULL-2
ECHO.将使用以下xml: & ECHOC {%c_we%}%xmls%{%c_i%}{\n}
start framework logviewer start %logfile%
ECHO.开始9008刷机... & call write qcedlxml %chkdev__port__qcedl% %storagetype% %sel__folder_path% %xmls%
ECHO.setbootablestoragedrive... & call ztetoolbox edlsetbootablestoragedrive %chkdev__port__qcedl% %storagetype%
ECHO.完成.
call framework logviewer end
ECHO.
ECHO.1.重启开机(默认)   2.清除数据并开机
call input choice #[1][2]
ECHO.
if "%choice%"=="2" ECHO.刷入misc... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
ECHO.
ECHOC {%c_s%}全部完成. {%c_i%}如果不开机或系统不正常, 请尝试进入官方Recovery手动清除数据. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU
:EDLFLASHFULL-FILENOTFOUND
ECHOC {%c_e%}选择的文件夹中缺少必需的文件(例如rawprogram0.xml). 请检查文件夹是否选择正确. {%c_h%}请保持设备稳定连接, 并按任意键重新选择...{%c_i%}{\n}& pause>nul & goto EDLFLASHFULL-1


:ROOT-REC
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.Root不开机恢复
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]   恢复方案: 恢复%bootpar%
ECHO.
ECHO.-注意事项
ECHO. 本功能适用于在使用本工具箱Root后不开机的情况下恢复自动备份的%bootpar%.
if "%parlayout:~0,2%"=="ab" ECHO. 备份文件将刷入ab两个槽位.
ECHO.
ECHOC {%c_h%}按任意键开始...{%c_i%}{\n}& pause>nul
ECHO.
ECHOC {%c_h%}请选择要恢复的%bootpar%备份文件...{%c_i%}{\n}& call sel file s %framework_workspace%\res\%product%\bak [img]
ECHOC {%c_h%}请手动进入9008...{%c_i%}{\n}& call chkdev qcedl rechk 1
if "%parlayout:~0,2%"=="ab" (
    ECHO.刷入%bootpar%_a... & call write qcedl %bootpar%_a %sel__file_path% %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
    ECHO.刷入%bootpar%_b... & call write qcedl %bootpar%_b %sel__file_path% %chkdev__port__qcedl%)
if not "%parlayout:~0,2%"=="ab" ECHO.刷入%bootpar%... & call write qcedl %bootpar% %sel__file_path% %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.重启... & call reboot qcedl system
ECHO.
ECHOC {%c_s%}全部完成. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:ROOT
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.获取Root
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO. [%model%]   Root方案: Magisk修补%bootpar%
ECHO.
ECHO.-注意事项
ECHO. Root前必须先解锁BL
ECHO. 本功能目前只支持Magisk修补
ECHO. 本功能不清除数据, 不区分系统版本
ECHO. 已Root请慎用本功能, 以免Magisk版本冲突无法开机
ECHO. 如需刷入其他版本Magisk, 请先恢复官方%bootpar%分区
ECHO. 如果Root后不开机, 请使用Root不开机恢复功能
ECHO.
ECHO.
ECHO.1.[推荐]使用工具箱内置的Magisk修补
ECHO.A.自选Magisk修补
ECHO.B.首次安装面具常见问题解答
ECHO.C.返回主菜单
ECHO.
call input choice #[1][A][B][C]
ECHO.
if "%choice%"=="1" set zippath=..\Magisk29.0.apk
if "%choice%"=="A" ECHOC {%c_h%}请选择Magisk卡刷包或apk...{%c_i%}{\n}& call sel file s %framework_workspace%\.. [zip][apk]
if "%choice%"=="A" set zippath=%sel__file_path%
if "%choice%"=="B" call open pic pic\magiskqa.jpg & goto ROOT
if "%choice%"=="C" goto MENU
ECHOC {%c_h%}请开机连接电脑, 并开启USB调试...{%c_i%}{\n}& call chkdev system rechk 1
start framework logviewer start %logfile%
ECHO.读取设备信息...
call info adb
call ztetoolbox chkproduct %info__adb__product%
if "%parlayout:~0,2%"=="ab" call slot system chk
if "%parlayout:~0,2%"=="ab" (set targetpar=%bootpar%_%slot__cur%) else (set targetpar=%bootpar%)
ECHOC {%c_we%}设备代号: %info__adb__product%{%c_i%}{\n}
ECHOC {%c_we%}安卓版本: %info__adb__androidver%{%c_i%}{\n}
ECHOC {%c_we%}目标分区: %targetpar%{%c_i%}{\n}
ECHO.重启到9008... & call reboot system qcedl rechk 1
ECHO.备份%targetpar%...
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
call read qcedl %targetpar% res\%product%\bak\%targetpar%_%baktime%.img notice %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
ECHO.文件已备份到bin\res\%product%\bak.
ECHO.Magisk修补... & call imgkit magiskpatch %framework_workspace%\res\%product%\bak\%targetpar%_%baktime%.img %tmpdir%\boot_patched.img %zippath% noprompt
ECHO.刷入%targetpar%... & call write qcedl %targetpar% %tmpdir%\boot_patched.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
call framework logviewer end
ECHO.
ECHOC {%c_s%}全部完成. {%c_h%}开机后请自行安装
if "%zippath%"=="..\Magisk29.0.apk" (ECHOC {%c_h%}工具箱目录中的Magisk29.0.apk. ) else (ECHOC {%c_h%}合适的Magisk APP. )
ECHOC {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:LOCKBL
set lockbl_chk=n
set lockbl_autoerase=n
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.上锁BL
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
if "%blplan%"=="n" ECHO.%model%暂不支持上锁BL. 按任意键返回... & pause>nul & goto MENU
if "%blplan%"=="special__P636A01" ECHO.%model%暂不支持上锁BL. 按任意键返回... & pause>nul & goto MENU
ECHO. [%model%]   上锁方案: %blplan%
ECHO.
if "%blplan%"=="avb" (
    set set unlockbl_avb_cpu=& set unlockbl_avb_uefisource=
    if "%product%"=="NP02J" set unlockbl_avb_cpu=8gen2& set unlockbl_avb_uefisource=Littlenine
    if "%product%"=="NX779J" set unlockbl_avb_cpu=8gen3& set unlockbl_avb_uefisource=Littlenine
    if "%product%"=="NX733J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX789J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX737J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX799J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NP05J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
)
if "%blplan%"=="avb" (
    if not exist res\%product%\abl_unlock.elf goto FATAL
    if not exist tool\Other\avbexploit\%unlockbl_avb_uefisource%\uefi_unlock_%unlockbl_avb_cpu%.img goto FATAL
    set unlockbl_avb_uefipath=tool\Other\avbexploit\%unlockbl_avb_uefisource%\uefi_unlock_%unlockbl_avb_cpu%.img
    if "%unlockbl_avb_uefisource%"=="Littlenine" ECHO.%model%暂不支持上锁BL. 按任意键返回... & pause>nul & goto MENU
)
ECHO.-上锁BL可能导致以下后果:
ECHO. 所有数据全部被格式化
ECHO. 无法开机
ECHO. ...
ECHO.
ECHO.-上锁BL需要作以下准备 (缺一不可):
ECHO. 将系统完全恢复官方
ECHO. 安装刷机驱动
ECHO. 保证数据线连接稳定
ECHO. 删除锁屏密码, 关闭查找设备, 退出官方账号和谷歌账号
ECHO. 备份所有个人数据到设备之外的地方
ECHO. 电脑退出搞机助手等一切和刷机相关的软件
ECHO. 掌握进入9008的操作方法
ECHO.
ECHO.-上锁BL是非常危险的行为, 任何情况下不建议上锁BL. 上锁自愿, 一切后果自负.
ECHO.
ECHO.
ECHOC {%c_h%}了解以上信息, 请按任意键开始上锁...{%c_i%}{\n}& pause>nul
ECHO.
:LOCKBL-1
ECHOC {%c_h%}请开机连接电脑, 并开启USB调试...{%c_i%}{\n}& call chkdev all rechk 1
if "%chkdev__mode%"=="system" goto LOCKBL-2
if "%blplan%"=="direct" (if not "%chkdev__mode%"=="fastboot" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto LOCKBL-1)
if "%blplan%"=="flashabl" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto LOCKBL-1)
if "%blplan%"=="efisp" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
if "%blplan%"=="special__ailsa_ii" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto LOCKBL-1)
ECHOC {%c_w%}不建议从%chkdev__mode%开始. %chkdev__mode%下工具无法获取正确的设备信息. 请手动开机连接电脑, 开启USB调试, 然后按Enter继续.{%c_i%}{\n}
ECHO.1.[推荐]从系统开始   2.从%chkdev__mode%开始
call input choice #[1][2]
if "%choice%"=="1" goto LOCKBL-1
if "%parlayout:~0,2%"=="ab" set slot__cur=unknown
goto LOCKBL-%blplan%-START
goto FATAL
:LOCKBL-2
ECHO.读取设备信息...
call info adb
call ztetoolbox chkproduct %info__adb__product%
if "%parlayout:~0,2%"=="ab" call slot system chk
ECHOC {%c_we%}设备代号: %info__adb__product%{%c_i%}{\n}
ECHOC {%c_we%}安卓版本: %info__adb__androidver%{%c_i%}{\n}
if "%parlayout:~0,2%"=="ab" ECHOC {%c_we%}当前槽位: %slot__cur%{%c_i%}{\n}
goto LOCKBL-%blplan%
goto FATAL
:LOCKBL-AVB
if "%presskeytoedl%"=="y" (goto LOCKBL-AVB-PRESSKEYTOEDL) else (goto LOCKBL-AVB-CMDTOEDL)
:LOCKBL-AVB-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto LOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto LOCKBL-AVB-START
:LOCKBL-AVB-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto LOCKBL-AVB-START
:LOCKBL-AVB-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
if "%storagetype%"=="ufs" (set targetlun=4) else (set targetlun=0)
if "%parlayout:~0,2%"=="ab" (set targetablpar=abl_%slot__cur%& set targetbootpar=boot_%slot__cur%& set targetvbmetapar=vbmeta_a& set targetpvmfwpar=pvmfw_%slot__cur%) else (set targetablpar=abl& set targetbootpar=boot& set targetvbmetapar=vbmeta& set targetpvmfwpar=pvmfw)
ECHO.备份gpt_main%targetlun%...
call partable readgpt qcedl %storagetype% %targetlun% gptmain res\%product%\bak\gpt_main%targetlun%.bin noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\gpt_main%targetlun%.bin res\%product%\bak\gpt_main%targetlun%_%baktime%.bin 1>>%logfile% 2>&1 || goto FATAL
ECHO.备份%targetablpar%...
call read qcedl %targetablpar% res\%product%\bak\%targetablpar%.img noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\%targetablpar%.img res\%product%\bak\%targetablpar%_%baktime%.img 1>>%logfile% 2>&1 || goto FATAL
ECHO.备份%targetbootpar%...
call read qcedl %targetbootpar% res\%product%\bak\%targetbootpar%.img noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\%targetbootpar%.img res\%product%\bak\%targetbootpar%_%baktime%.img 1>>%logfile% 2>&1 || goto FATAL
ECHO.文件已备份到bin\res\%product%\bak.
ECHO.修改gpt_main%targetlun%...
copy /Y res\%product%\bak\gpt_main%targetlun%.bin %tmpdir%\tmp.bin 1>>%logfile% 2>&1 || goto FATAL
gpttool.exe -p %tmpdir%\tmp.bin -f rmpar:name:%targetvbmetapar% 1>>%logfile% 2>&1 || goto FATAL
gpttool.exe -p %tmpdir%\tmp.bin -f rmpar:name:%targetpvmfwpar%  1>>%logfile% 2>&1 || ECHOC {%c_we%}未删除%targetpvmfwpar%分区...{%c_i%}{\n}&& call log %logger% W 未删除%targetpvmfwpar%分区
ECHO.刷入gpt_main%targetlun%... & call partable writegpt qcedl %storagetype% %targetlun% %tmpdir%\tmp.bin %chkdev__port__qcedl%
ECHO.刷入旧版abl... & call write qcedl %targetablpar% res\%product%\abl_unlock.elf %chkdev__port__qcedl%
ECHO.刷入解锁uefi... & call write qcedl %targetbootpar% %unlockbl_avb_uefipath% %chkdev__port__qcedl%
if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
if "%unlockbl_avb_uefisource%"=="anonymous1" goto LOCKBL-AVB-FBLOCK
goto FATAL
:LOCKBL-AVB-FBLOCK
ECHO.设备将进入Fastboot. 如果没有自动进入, 请手动进入. 进入后请手动选择检查Fastboot连接. 无论能否检查到连接, 请不要关闭脚本, 请按提示继续操作.
:LOCKBL-AVB-FBLOCK-1
ECHO.1.检查Fastboot连接   2.多次检查仍检查不到   3.查看什么是Fastboot
call input choice #[1][2][3]
if "%choice%"=="2" ECHOC {%c_e%}上锁失败. 请加交流群反馈.{%c_i%}{\n}& goto LOCKBL-AVB-RESTORE
if "%choice%"=="3" call open pic pic\fastboot.jpg & goto LOCKBL-AVB-FBLOCK-1
fastboot.exe devices -l 2>&1 | find "fastboot" 1>nul 2>nul || ECHOC {%c_e%}设备未连接. {%c_i%}请查看设备管理器, 尝试拔插设备和检查驱动是否安装.{%c_i%}{\n}&& goto LOCKBL-AVB-FBLOCK-1
call chkdev fastboot
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="no" ECHOC {%c_s%}你的设备已上锁. {%c_i%}{\n}& set lockbl_chk=y& goto LOCKBL-AVB-RESTORE
ECHO.正在执行上锁命令. 如果设备上出现确认上锁提示, 请按音量键选择"LOCK THE BOOTLOADER"(若不能清晰显示则选择靠下的选项), 然后按电源键确认. 确认后设备会自动重启, 无论能否正常开机, 请不要关闭脚本, 请按提示继续操作.
fastboot.exe flashing lock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行上锁命令失败. 请查看日志.{%c_i%}{\n}
:LOCKBL-AVB-FBLOCK-2
ECHO.1.我已确认上锁   2.我没有看到确认上锁提示
call input choice [1][2]
if "%choice%"=="1" set lockbl_autoerase=y
if "%choice%"=="2" ECHOC {%c_e%}上锁失败. 稍后请加交流群反馈.{%c_i%}{\n}
goto LOCKBL-AVB-RESTORE
:LOCKBL-AVB-RESTORE
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续手动操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式"文档)...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
ECHO.恢复gpt_main%targetlun%... & call partable writegpt qcedl %storagetype% %targetlun% res\%product%\bak\gpt_main%targetlun%.bin %chkdev__port__qcedl%
ECHO.恢复%targetablpar%... & call write qcedl %targetablpar% res\%product%\bak\%targetablpar%.img %chkdev__port__qcedl%
ECHO.恢复%targetbootpar%... & call write qcedl %targetbootpar% res\%product%\bak\%targetbootpar%.img %chkdev__port__qcedl%
if "%parlayout:~0,2%"=="ab" ECHO.激活%slot__cur%槽位... & call slot qcedl set %slot__cur%
if "%lockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto LOCKBL-DONE
:LOCKBL-EFISP
if "%presskeytoedl%"=="y" (goto LOCKBL-EFISP-PRESSKEYTOEDL) else (goto LOCKBL-EFISP-CMDTOEDL)
:LOCKBL-EFISP-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto LOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto LOCKBL-EFISP-START
:LOCKBL-EFISP-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto LOCKBL-EFISP-START
:LOCKBL-EFISP-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
::if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
ECHO.备份abl_%slot__cur%... & call read qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.img notice %chkdev__port__qcedl%
ECHO.备份efisp... & call read qcedl efisp res\%product%\bak\efisp_%baktime%.img notice %chkdev__port__qcedl%
ECHO.文件已备份到bin\res\%product%\bak.
ECHO.刷入旧版abl... & call write qcedl abl_%slot__cur% res\%product%\abl_unlock.elf %chkdev__port__qcedl%
ECHO.刷入上锁程序... & call write qcedl efisp tool\Other\8e5gbl\gbl_lock.efi %chkdev__port__qcedl%
::if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启(如果提示失败请选择选项2)... & call reboot qcedl system
ECHO.设备开机后不出现黄色解锁警告, 即为上锁成功. 否则请加入交流群反馈. 等待5秒钟... & TIMEOUT /T 5 /NOBREAK>nul
set unlockbl_autoerase=y
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续手动操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式"文档)...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
::if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
ECHO.恢复abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.img %chkdev__port__qcedl%
ECHO.清空efisp... & call write qcedl efisp tool\Other\8e5gbl\efisp_empty.img %chkdev__port__qcedl%
if "%unlockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto LOCKBL-DONE
:LOCKBL-special__ailsa_ii
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto LOCKBL-special__ailsa_ii-START
:LOCKBL-special__ailsa_ii-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
ECHO.备份aboot... & call read qcedl aboot res\%product%\bak\aboot_%baktime%.mbn notice %chkdev__port__qcedl%
ECHO.备份fbop...  & call read qcedl fbop  res\%product%\bak\fbop_%baktime%.img  notice %chkdev__port__qcedl%
::ECHO.备份frp...   & call read qcedl frp   res\%product%\bak\frp_%baktime%.img   notice %chkdev__port__qcedl%
::ECHO.修补frp开启OEM解锁... & call imgkit patchfrp res\%product%\bak\frp_%baktime%.img %tmpdir%\frp_oemunlockon.img oemunlockon noprompt
ECHO.刷入解锁aboot... & call write qcedl aboot res\%product%\aboot_unlock.mbn %chkdev__port__qcedl%
ECHO.刷入解锁fbop...  & call write qcedl fbop  res\%product%\fbop_unlock.img  %chkdev__port__qcedl%
::ECHO.刷入解锁frp...   & call write qcedl frp   %tmpdir%\frp_oemunlockon.img        %chkdev__port__qcedl%
ECHO.重启开机... & call reboot qcedl system
ECHO.设备将自动重启开机. 开机后如果没有开启USB调试, 请开启USB调试. 如果无法开机, 请加交流群反馈.
call chkdev system rechk 1
ECHO.重启到Fastboot... & call reboot system fastboot rechk 1
ECHO.执行上锁命令...
fastboot.exe oem lock 1>%tmpdir%\output.txt 2>&1 || ECHOC {%c_e%}执行上锁命令失败. 请查看日志.{%c_i%}{\n}
type %tmpdir%\output.txt>>%logfile%
find "Device already : locked!" "%tmpdir%\output.txt" 1>nul 2>nul && ECHOC {%c_s%}你的设备已上锁.{%c_i%}{\n}&& set lockbl_chk=y&& goto LOCKBL-DONE
goto LOCKBL-DONE
:LOCKBL-FLASHABL
if "%presskeytoedl%"=="y" (goto LOCKBL-FLASHABL-PRESSKEYTOEDL) else (goto LOCKBL-FLASHABL-CMDTOEDL)
:LOCKBL-FLASHABL-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot bootloader 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto LOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto LOCKBL-FLASHABL-START
:LOCKBL-FLASHABL-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto LOCKBL-FLASHABL-START
:LOCKBL-FLASHABL-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
if not "%parlayout:~0,2%"=="ab" (
    ECHO.备份abl... & call read qcedl abl res\%product%\bak\abl_%baktime%.elf notice %chkdev__port__qcedl%
    ECHO.文件已备份到bin\res\%product%\bak.
    ECHO.刷入解锁abl... & call write qcedl abl res\%product%\abl_unlock.elf %chkdev__port__qcedl%)
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
if "%parlayout:~0,2%"=="ab" (
    ECHO.备份abl_%slot__cur%... & call read qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.elf notice %chkdev__port__qcedl%
    ECHO.文件已备份到bin\res\%product%\bak.
    ECHO.刷入解锁abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\abl_unlock.elf %chkdev__port__qcedl%)
if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
ECHO.设备将进入Fastboot. 如果没有自动进入, 请手动进入. 进入后请手动选择检查Fastboot连接. 无论能否检查到连接, 请不要关闭脚本, 请按提示继续操作.
:LOCKBL-FLASHABL-4
ECHO.1.检查Fastboot连接   2.多次检查仍检查不到   3.查看什么是Fastboot
call input choice #[1][2][3]
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 请加交流群反馈.{%c_i%}{\n}& goto LOCKBL-FLASHABL-1
if "%choice%"=="3" call open pic pic\fastboot.jpg & goto LOCKBL-FLASHABL-4
fastboot.exe devices -l 2>&1 | find "fastboot" 1>nul 2>nul || ECHOC {%c_e%}设备未连接. {%c_i%}请查看设备管理器, 尝试拔插设备, 更换数据线和插口, 和检查驱动是否安装.{%c_i%}{\n}&& goto LOCKBL-FLASHABL-4
call chkdev fastboot
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="no" ECHOC {%c_s%}你的设备已上锁. {%c_i%}{\n}& set lockbl_chk=y& goto LOCKBL-FLASHABL-1
ECHO.正在执行上锁命令. 如果设备上出现确认上锁提示, 请按音量键选择"LOCK THE BOOTLOADER", 然后按电源键确认. 确认后设备会自动重启, 无论能否正常开机, 请不要关闭脚本, 请按提示继续操作.
fastboot.exe flashing lock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行上锁命令失败. 请查看日志.{%c_i%}{\n}
:LOCKBL-FLASHABL-2
ECHO.1.我已确认上锁   2.我没有看到确认上锁提示
call input choice [1][2]
::if "%choice%"=="3" call open pic pic\lockbl.jpg & goto LOCKBL-FLASHABL-2
if "%choice%"=="1" set lockbl_autoerase=y
if "%choice%"=="2" ECHOC {%c_e%}上锁失败. 稍后请加交流群反馈.{%c_i%}{\n}
goto LOCKBL-FLASHABL-1
:LOCKBL-FLASHABL-1
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式")...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
if not "%parlayout:~0,2%"=="ab" (
    ECHO.恢复abl... & call write qcedl abl res\%product%\bak\abl_%baktime%.elf %chkdev__port__qcedl%)
if "%parlayout:~0,2%"=="ab" (
    ECHO.恢复abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.elf %chkdev__port__qcedl%
    ECHO.激活%slot__cur%槽位... & call slot qcedl set %slot__cur%)
if "%lockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto LOCKBL-DONE
:LOCKBL-DIRECT
ECHO.重启到fastboot... & call reboot system fastboot rechk 1
:LOCKBL-DIRECT-START
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="no" ECHOC {%c_s%}你的设备已上锁. {%c_i%}{\n}& set lockbl_chk=y& goto LOCKBL-DONE
ECHO.正在执行上锁命令. 如果设备上出现确认上锁提示, 请按音量键选择"LOCK THE BOOTLOADER", 然后按电源键确认. 如果没有, 说明上锁失败.
fastboot.exe flashing lock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行上锁命令失败. 请查看日志.{%c_i%}{\n}
ECHO.1.我已确认上锁   2.我没有看到确认上锁提示
call input choice [1][2]
if "%choice%"=="2" ECHOC {%c_e%}上锁失败. 请加交流群反馈.{%c_i%}{\n}
goto LOCKBL-DONE
:LOCKBL-DONE
if "%lockbl_chk%"=="y" goto LOCKBL-DONE-1
::ECHO.
::ECHO.1.检查是否上锁成功
::ECHO.2.我确定已经上锁成功
::call input choice #[1][2]
::ECHO.
::if "%choice%"=="1" goto LOCKBL-1
:LOCKBL-DONE-1
ECHO. & ECHOC {%c_s%}全部完成. {%c_i%}上锁后如果不开机, 请进入Recovery清除所有数据恢复出厂. 恢复出厂后首次开机较慢, 请耐心等待. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:UNLOCKBL
set unlockbl_chk=n
set unlockbl_autoerase=n
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.解锁BL
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
if "%blplan%"=="n" ECHO.%model%暂不支持解锁BL. 按任意键返回... & pause>nul & goto MENU
if "%blplan%"=="special__P636A01" ECHO.%model%的解锁BL方案还有待研究. 如果需要Root和框架, 请在yhcres.top下载官改包, 通过9008刷入, 恢复出厂开机即可. & ECHO. & ECHOC {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU
ECHO. [%model%]   解锁方案: %blplan%
ECHO.
if "%blplan%"=="avb" (
    set set unlockbl_avb_cpu=& set unlockbl_avb_uefisource=
    if "%product%"=="NP02J" set unlockbl_avb_cpu=8gen2& set unlockbl_avb_uefisource=Littlenine
    if "%product%"=="NX779J" set unlockbl_avb_cpu=8gen3& set unlockbl_avb_uefisource=Littlenine
    if "%product%"=="NX733J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX789J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX737J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NX799J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
    if "%product%"=="NP05J" set unlockbl_avb_cpu=8e& set unlockbl_avb_uefisource=anonymous1
)
if "%blplan%"=="avb" (
    if not exist res\%product%\abl_unlock.elf goto FATAL
    if not exist tool\Other\avbexploit\%unlockbl_avb_uefisource%\uefi_unlock_%unlockbl_avb_cpu%.img goto FATAL
    set unlockbl_avb_uefipath=tool\Other\avbexploit\%unlockbl_avb_uefisource%\uefi_unlock_%unlockbl_avb_cpu%.img
    if "%unlockbl_avb_uefisource%"=="Littlenine" ECHO.本方案解锁文件来源于酷安@Littlenine. 禁止滥用& ECHOC {%c_w%}本方案目前不支持上锁BL, 解锁后将无法重新上锁, 请慎重考虑!{%c_i%}{\n}& ECHO.
)
ECHO.-解锁BL可能导致以下后果:
ECHO. 系统指纹不可用(需重新校准或上锁BL,屏下超声波指纹目前市面无校准工具)
ECHO. TEE损坏
ECHO. 所有数据全部被格式化
ECHO. 官方系统更新不可用
ECHO. 失去保修
ECHO. 开机出现黄色解锁警告
ECHO. 解锁后再上锁是非常危险的行为
ECHO. ...
ECHO.
ECHO.-解锁BL需要作以下准备 (缺一不可):
ECHO. 安装刷机驱动
ECHO. 保证数据线连接稳定
if "%product%"=="NX563J" ECHO. 在yhcres.top下载V6.28版本9008包刷入& ECHO. (位置: 刷机包-努比亚-努比亚Z17-NubiaUI-9008线刷救砖包)
if "%blplan_frp%"=="n" ECHO. 在开发者选项中开启OEM解锁选项
ECHO. 删除锁屏密码, 关闭查找设备, 退出官方账号和谷歌账号
ECHO. 备份所有个人数据到设备之外的地方
ECHO. 电脑退出搞机助手等一切和刷机相关的软件
ECHO. 掌握进入9008的操作方法
ECHO. 建议先备份全分区以防意外
ECHO.
ECHO.-请严格按提示操作, 遇到问题不要中途关闭, 请截图并加交流反馈群反馈.
ECHO.
ECHO.
ECHOC {%c_h%}了解以上信息, 请按任意键开始解锁...{%c_i%}{\n}& pause>nul
ECHO.
:UNLOCKBL-1
ECHOC {%c_h%}请开机连接电脑, 并开启USB调试...{%c_i%}{\n}& call chkdev all rechk 1
if "%chkdev__mode%"=="system" goto UNLOCKBL-2
if "%blplan%"=="direct" (if not "%chkdev__mode%"=="fastboot" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
if "%blplan%"=="flashabl" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
if "%blplan%"=="efisp" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
if "%blplan%"=="avb" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
if "%blplan%"=="special__ailsa_ii" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & goto UNLOCKBL-1)
ECHOC {%c_w%}不建议从%chkdev__mode%开始. %chkdev__mode%下工具无法获取正确的设备信息. 请手动开机连接电脑, 开启USB调试, 然后按Enter继续.{%c_i%}{\n}
ECHO.1.[推荐]从系统开始   2.从%chkdev__mode%开始
call input choice #[1][2]
if "%choice%"=="1" goto UNLOCKBL-1
if "%parlayout:~0,2%"=="ab" set slot__cur=unknown
goto UNLOCKBL-%blplan%-START
goto FATAL
:UNLOCKBL-2
ECHO.读取设备信息...
call info adb
call ztetoolbox chkproduct %info__adb__product%
if "%parlayout:~0,2%"=="ab" call slot system chk
ECHOC {%c_we%}设备代号: %info__adb__product%{%c_i%}{\n}
ECHOC {%c_we%}安卓版本: %info__adb__androidver%{%c_i%}{\n}
if "%parlayout:~0,2%"=="ab" ECHOC {%c_we%}当前槽位: %slot__cur%{%c_i%}{\n}
goto UNLOCKBL-%blplan%
goto FATAL
:UNLOCKBL-AVB
if "%presskeytoedl%"=="y" (goto UNLOCKBL-AVB-PRESSKEYTOEDL) else (goto UNLOCKBL-AVB-CMDTOEDL)
:UNLOCKBL-AVB-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto UNLOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto UNLOCKBL-AVB-START
:UNLOCKBL-AVB-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto UNLOCKBL-AVB-START
:UNLOCKBL-AVB-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
if "%storagetype%"=="ufs" (set targetlun=4) else (set targetlun=0)
if "%parlayout:~0,2%"=="ab" (set targetablpar=abl_%slot__cur%& set targetbootpar=boot_%slot__cur%& set targetvbmetapar=vbmeta_a& set targetpvmfwpar=pvmfw_%slot__cur%) else (set targetablpar=abl& set targetbootpar=boot& set targetvbmetapar=vbmeta& set targetpvmfwpar=pvmfw)
ECHO.备份gpt_main%targetlun%...
call partable readgpt qcedl %storagetype% %targetlun% gptmain res\%product%\bak\gpt_main%targetlun%.bin noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\gpt_main%targetlun%.bin res\%product%\bak\gpt_main%targetlun%_%baktime%.bin 1>>%logfile% 2>&1 || goto FATAL
ECHO.备份%targetablpar%...
call read qcedl %targetablpar% res\%product%\bak\%targetablpar%.img noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\%targetablpar%.img res\%product%\bak\%targetablpar%_%baktime%.img 1>>%logfile% 2>&1 || goto FATAL
ECHO.备份%targetbootpar%...
call read qcedl %targetbootpar% res\%product%\bak\%targetbootpar%.img noprompt %chkdev__port__qcedl%
copy /Y res\%product%\bak\%targetbootpar%.img res\%product%\bak\%targetbootpar%_%baktime%.img 1>>%logfile% 2>&1 || goto FATAL
ECHO.文件已备份到bin\res\%product%\bak.
ECHO.修改gpt_main%targetlun%...
copy /Y res\%product%\bak\gpt_main%targetlun%.bin %tmpdir%\tmp.bin 1>>%logfile% 2>&1 || goto FATAL
gpttool.exe -p %tmpdir%\tmp.bin -f rmpar:name:%targetvbmetapar% 1>>%logfile% 2>&1 || goto FATAL
gpttool.exe -p %tmpdir%\tmp.bin -f rmpar:name:%targetpvmfwpar%  1>>%logfile% 2>&1 || ECHOC {%c_we%}未删除%targetpvmfwpar%分区...{%c_i%}{\n}&& call log %logger% W 未删除%targetpvmfwpar%分区
ECHO.刷入gpt_main%targetlun%... & call partable writegpt qcedl %storagetype% %targetlun% %tmpdir%\tmp.bin %chkdev__port__qcedl%
ECHO.刷入旧版abl... & call write qcedl %targetablpar% res\%product%\abl_unlock.elf %chkdev__port__qcedl%
ECHO.刷入解锁uefi... & call write qcedl %targetbootpar% %unlockbl_avb_uefipath% %chkdev__port__qcedl%
if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
if "%unlockbl_avb_uefisource%"=="anonymous1" goto UNLOCKBL-AVB-FBUNLOCK
if "%unlockbl_avb_uefisource%"=="Littlenine" goto UNLOCKBL-AVB-AUTOUNLOCK
goto FATAL
:UNLOCKBL-AVB-FBUNLOCK
ECHO.设备将进入Fastboot. 如果没有自动进入, 请手动进入. 进入后请手动选择检查Fastboot连接. 无论能否检查到连接, 请不要关闭脚本, 请按提示继续操作.
:UNLOCKBL-AVB-FBUNLOCK-1
ECHO.1.检查Fastboot连接   2.多次检查仍检查不到   3.查看什么是Fastboot
call input choice #[1][2][3]
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 请加交流群反馈.{%c_i%}{\n}& goto UNLOCKBL-AVB-RESTORE
if "%choice%"=="3" call open pic pic\fastboot.jpg & goto UNLOCKBL-AVB-FBUNLOCK-1
fastboot.exe devices -l 2>&1 | find "fastboot" 1>nul 2>nul || ECHOC {%c_e%}设备未连接. {%c_i%}请查看设备管理器, 尝试拔插设备, 更换数据线和插口, 和检查驱动是否安装.{%c_i%}{\n}&& goto UNLOCKBL-AVB-FBUNLOCK-1
call chkdev fastboot
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="yes" ECHOC {%c_s%}你的设备已解锁. {%c_i%}{\n}& set unlockbl_chk=y& goto UNLOCKBL-AVB-RESTORE
ECHO.正在执行解锁命令. 如果设备上出现确认解锁提示, 请按音量键选择"UNLOCK THE BOOTLOADER"(若不能清晰显示则选择靠下的选项), 然后按电源键确认. 确认后设备会自动重启, 无论能否正常开机, 请不要关闭脚本, 请按提示继续操作.
fastboot.exe flashing unlock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行解锁命令失败. 请查看日志.{%c_i%}{\n}
:UNLOCKBL-AVB-FBUNLOCK-2
ECHO.1.我已确认解锁   2.我没有看到确认解锁提示   3.查看什么是解锁提示
call input choice [1][2][3]
if "%choice%"=="3" call open pic pic\unlockbl.jpg & goto UNLOCKBL-AVB-FBUNLOCK-2
if "%choice%"=="1" set unlockbl_autoerase=y
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 稍后请加交流群反馈.{%c_i%}{\n}
goto UNLOCKBL-AVB-RESTORE
:UNLOCKBL-AVB-AUTOUNLOCK
ECHO.请等待15秒, 以确保解锁程序执行完成. 设备将卡在第一屏或保持黑屏 (不会反复重启).
ECHO.后续开机时请留意是否出现黄色解锁警告, 出现即代表解锁成功. 有问题请加交流群反馈.
set num=1
:UNLOCKBL-AVB-AUTOUNLOCK-1
TIMEOUT /T 1 /NOBREAK>nul& ECHOC {%c_i%}%num% 
if "%num%"=="15" ECHO.& goto UNLOCKBL-AVB-RESTORE
set /a num+=1& goto UNLOCKBL-AVB-AUTOUNLOCK-1
:UNLOCKBL-AVB-RESTORE
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续手动操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式"文档)...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
ECHO.恢复gpt_main%targetlun%... & call partable writegpt qcedl %storagetype% %targetlun% res\%product%\bak\gpt_main%targetlun%.bin %chkdev__port__qcedl%
ECHO.恢复%targetablpar%... & call write qcedl %targetablpar% res\%product%\bak\%targetablpar%.img %chkdev__port__qcedl%
ECHO.恢复%targetbootpar%... & call write qcedl %targetbootpar% res\%product%\bak\%targetbootpar%.img %chkdev__port__qcedl%
if "%parlayout:~0,2%"=="ab" ECHO.激活%slot__cur%槽位... & call slot qcedl set %slot__cur%
if "%unlockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto UNLOCKBL-DONE
:UNLOCKBL-EFISP
if "%presskeytoedl%"=="y" (goto UNLOCKBL-EFISP-PRESSKEYTOEDL) else (goto UNLOCKBL-EFISP-CMDTOEDL)
:UNLOCKBL-EFISP-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto UNLOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto UNLOCKBL-EFISP-START
:UNLOCKBL-EFISP-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto UNLOCKBL-EFISP-START
:UNLOCKBL-EFISP-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
::if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
ECHO.备份abl_%slot__cur%... & call read qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.img notice %chkdev__port__qcedl%
ECHO.备份efisp... & call read qcedl efisp res\%product%\bak\efisp_%baktime%.img notice %chkdev__port__qcedl%
ECHO.文件已备份到bin\res\%product%\bak.
ECHO.刷入旧版abl... & call write qcedl abl_%slot__cur% res\%product%\abl_unlock.elf %chkdev__port__qcedl%
ECHO.刷入解锁程序... & call write qcedl efisp tool\Other\8e5gbl\gbl_unlock.efi %chkdev__port__qcedl%
::if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启(如果提示失败请选择选项2)... & call reboot qcedl system
ECHOC {%c_i%}设备开机过程中将出现黄色解锁警告. {%c_i%}请按脚本提示选择, 请勿关闭脚本.{%c_i%}{\n}
:UNLOCKBL-EFISP-4
ECHO.1.我已看到解锁警告   2.我没有看到解锁警告   3.查看示例图
call input choice [1][2]#[3]
if "%choice%"=="3" call open pic pic\blunlockedfeatures.jpg & goto UNLOCKBL-EFISP-4
if "%choice%"=="1" set unlockbl_autoerase=y
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 请加交流群反馈.{%c_i%}{\n}
:UNLOCKBL-EFISP-1
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续手动操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式"文档)...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
::if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
ECHO.恢复abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.img %chkdev__port__qcedl%
ECHO.清空efisp... & call write qcedl efisp tool\Other\8e5gbl\efisp_empty.img %chkdev__port__qcedl%
if "%unlockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto UNLOCKBL-DONE
:UNLOCKBL-FLASHABL
if "%presskeytoedl%"=="y" (goto UNLOCKBL-FLASHABL-PRESSKEYTOEDL) else (goto UNLOCKBL-FLASHABL-CMDTOEDL)
:UNLOCKBL-FLASHABL-PRESSKEYTOEDL
ECHOC {%c_h%}现在请同时按住设备音量加和音量减, 不要松手, 然后在电脑上按任意键继续. 在脚本提示可以松手之前请不要松手...{%c_i%}{\n}& pause>nul
ECHO.重启... & adb.exe reboot bootloader 1>>%logfile% 2>&1 || ECHOC {%c_e%}重启失败. 请保持设备连接稳定. {%c_h%}按任意键重试...{%c_i%}{\n}&& pause>nul && goto UNLOCKBL
ECHO.注意: 现在设备应当是完全黑屏状态. 只要亮屏即为失败, 只要亮屏请立刻断开数据线, 关闭脚本, 再试一次.
ECHOC {%c_h%}请保持长按音量加减...{%c_i%}{\n}
call chkdev qcedl rechk 1
ECHOC {%c_h%}现在你可以松手了{%c_i%}{\n}
goto UNLOCKBL-FLASHABL-START
:UNLOCKBL-FLASHABL-CMDTOEDL
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto UNLOCKBL-FLASHABL-START
:UNLOCKBL-FLASHABL-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
if "%blplan_frp%"=="y" ECHO.备份frp... & call read qcedl frp res\%product%\bak\frp_%baktime%.img notice %chkdev__port__qcedl%
if not "%parlayout:~0,2%"=="ab" (
    ECHO.备份abl... & call read qcedl abl res\%product%\bak\abl_%baktime%.elf notice %chkdev__port__qcedl%
    ECHO.文件已备份到bin\res\%product%\bak.
    ECHO.刷入解锁abl... & call write qcedl abl res\%product%\abl_unlock.elf %chkdev__port__qcedl%)
if "%parlayout:~0,2%"=="ab" (if "%slot__cur%"=="unknown" ECHO.检查当前槽位... & call slot qcedl chk)
if "%parlayout:~0,2%"=="ab" (
    ECHO.备份abl_%slot__cur%... & call read qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.elf notice %chkdev__port__qcedl%
    ECHO.文件已备份到bin\res\%product%\bak.
    ECHO.刷入解锁abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\abl_unlock.elf %chkdev__port__qcedl%)
if "%blplan_frp%"=="y" ECHO.刷入解锁frp... & call write qcedl frp tool\Android\frp_unlock.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
ECHO.设备将进入Fastboot. 如果没有自动进入, 请手动进入. 进入后请手动选择检查Fastboot连接. 无论能否检查到连接, 请不要关闭脚本, 请按提示继续操作.
:UNLOCKBL-FLASHABL-4
ECHO.1.检查Fastboot连接   2.多次检查仍检查不到   3.查看什么是Fastboot
call input choice #[1][2][3]
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 请加交流群反馈.{%c_i%}{\n}& goto UNLOCKBL-FLASHABL-1
if "%choice%"=="3" call open pic pic\fastboot.jpg & goto UNLOCKBL-FLASHABL-4
fastboot.exe devices -l 2>&1 | find "fastboot" 1>nul 2>nul || ECHOC {%c_e%}设备未连接. {%c_i%}请查看设备管理器, 尝试拔插设备和检查驱动是否安装.{%c_i%}{\n}&& goto UNLOCKBL-FLASHABL-4
call chkdev fastboot
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="yes" ECHOC {%c_s%}你的设备已解锁. {%c_i%}{\n}& set unlockbl_chk=y& goto UNLOCKBL-FLASHABL-1
ECHO.正在执行解锁命令. 如果设备上出现确认解锁提示, 请按音量键选择"UNLOCK THE BOOTLOADER", 然后按电源键确认. 确认后设备会自动重启, 无论能否正常开机, 请不要关闭脚本, 请按提示继续操作.
fastboot.exe flashing unlock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行解锁命令失败. 请查看日志.{%c_i%}{\n}
:UNLOCKBL-FLASHABL-2
ECHO.1.我已确认解锁   2.我没有看到确认解锁提示   3.查看什么是解锁提示
call input choice [1][2][3]
if "%choice%"=="3" call open pic pic\unlockbl.jpg & goto UNLOCKBL-FLASHABL-2
if "%choice%"=="1" set unlockbl_autoerase=y
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 稍后请加交流群反馈.{%c_i%}{\n}
goto UNLOCKBL-FLASHABL-1
:UNLOCKBL-FLASHABL-1
ECHOC {%c_w%}本工具箱由 酷安@某贼 制作, 完全免费, 禁止倒卖{%c_i%}{\n}
ECHOC {%c_i%}设备现在处于非正常状态, 下面将为你恢复设备. 请不要关闭脚本, 请按提示继续手动操作, 否则后果自负. {%c_h%}无需等待开机, 无论设备能否开机, 请现在手动进入9008 (不会进请参考工具箱目录中的"如何进入各个模式"文档)...{%c_i%}{\n}& call chkdev qcedl rechk 1
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
if "%blplan_frp%"=="y" ECHO.恢复frp... & call write qcedl frp res\%product%\bak\frp_%baktime%.img %chkdev__port__qcedl%
if not "%parlayout:~0,2%"=="ab" (
    ECHO.恢复abl... & call write qcedl abl res\%product%\bak\abl_%baktime%.elf %chkdev__port__qcedl%)
if "%parlayout:~0,2%"=="ab" (
    ECHO.恢复abl_%slot__cur%... & call write qcedl abl_%slot__cur% res\%product%\bak\abl_%slot__cur%_%baktime%.elf %chkdev__port__qcedl%
    ECHO.激活%slot__cur%槽位... & call slot qcedl set %slot__cur%)
if "%unlockbl_autoerase%"=="y" ECHO.设置自动恢复出厂... & call write qcedl misc tool\Android\misc_wipedata.img %chkdev__port__qcedl%
ECHO.重启... & call reboot qcedl system
goto UNLOCKBL-DONE
:UNLOCKBL-special__ailsa_ii
ECHO.重启到9008... & call reboot system qcedl rechk 1
goto UNLOCKBL-special__ailsa_ii-START
:UNLOCKBL-special__ailsa_ii-START
ECHO.发送引导... & call write qcedlsendfh %chkdev__port__qcedl% %framework_workspace%\res\%product%\devprg
for /f %%a in ('gettime.exe ^| find "."') do set baktime=%%a
ECHO.备份aboot... & call read qcedl aboot res\%product%\bak\aboot_%baktime%.mbn notice %chkdev__port__qcedl%
ECHO.备份fbop...  & call read qcedl fbop  res\%product%\bak\fbop_%baktime%.img  notice %chkdev__port__qcedl%
::ECHO.备份frp...   & call read qcedl frp   res\%product%\bak\frp_%baktime%.img   notice %chkdev__port__qcedl%
::ECHO.修补frp开启OEM解锁... & call imgkit patchfrp res\%product%\bak\frp_%baktime%.img %tmpdir%\frp_oemunlockon.img oemunlockon noprompt
ECHO.刷入解锁aboot... & call write qcedl aboot res\%product%\aboot_unlock.mbn %chkdev__port__qcedl%
ECHO.刷入解锁fbop...  & call write qcedl fbop  res\%product%\fbop_unlock.img  %chkdev__port__qcedl%
::ECHO.刷入解锁frp...   & call write qcedl frp   %tmpdir%\frp_oemunlockon.img        %chkdev__port__qcedl%
ECHO.重启开机... & call reboot qcedl system
ECHO.设备将自动重启开机. 开机后如果没有开启USB调试, 请开启USB调试. 如果无法开机, 请加交流群反馈.
call chkdev system rechk 1
ECHO.重启到Fastboot... & call reboot system fastboot rechk 1
ECHO.执行解锁命令...
fastboot.exe oem unlock 1>%tmpdir%\output.txt 2>&1 || ECHOC {%c_e%}执行解锁命令失败. 请查看日志.{%c_i%}{\n}
type %tmpdir%\output.txt>>%logfile%
find "Device already : unlocked!" "%tmpdir%\output.txt" 1>nul 2>nul && ECHOC {%c_s%}你的设备已解锁.{%c_i%}{\n}&& set unlockbl_chk=y&& goto UNLOCKBL-DONE
ECHO.如果设备上出现确认解锁提示, 请按音量键选择"Yes", 然后按电源键确认. 确认后设备会自动重启并恢复出厂设置.
ECHO.1.我已确认解锁   2.我没有看到确认解锁提示
call input choice [1][2]
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 稍后请加交流群反馈.{%c_i%}{\n}
goto UNLOCKBL-DONE
:UNLOCKBL-DIRECT
ECHO.重启到fastboot... & call reboot system fastboot rechk 1
:UNLOCKBL-DIRECT-START
ECHO.读取设备信息... & call info fastboot
if "%info__fastboot__unlocked%"=="yes" ECHOC {%c_s%}你的设备已解锁. {%c_i%}{\n}& set unlockbl_chk=y& goto UNLOCKBL-DONE
ECHO.正在执行解锁命令. 如果设备上出现确认解锁提示, 请按音量键选择"UNLOCK THE BOOTLOADER", 然后按电源键确认. 如果没有, 说明解锁失败.
fastboot.exe flashing unlock 1>>%logfile% 2>&1 || ECHOC {%c_e%}执行解锁命令失败. 请查看日志.{%c_i%}{\n}
ECHO.1.我已确认解锁   2.我没有看到确认解锁提示
call input choice [1][2]
if "%choice%"=="2" ECHOC {%c_e%}解锁失败. 请加交流群反馈.{%c_i%}{\n}
goto UNLOCKBL-DONE
:UNLOCKBL-DONE
if "%unlockbl_chk%"=="y" goto UNLOCKBL-DONE-1
ECHO.
::ECHO.1.[推荐]检查是否解锁成功
ECHO.1.查看已解锁BL的特征
ECHO.2.继续
call input choice #[1][2]
ECHO.
::if "%choice%"=="1" goto UNLOCKBL-1
if "%choice%"=="1" call open pic pic\blunlockedfeatures.jpg & goto UNLOCKBL-DONE
:UNLOCKBL-DONE-1
ECHO. & ECHOC {%c_s%}全部完成. {%c_i%}解锁后开机出现黄字属正常现象. 解锁后如果不开机, 请进入Recovery清除所有数据恢复出厂. 恢复出厂后首次开机较慢, 请耐心等待. {%c_h%}按任意键返回...{%c_i%}{\n}& pause>nul & goto MENU


:SELDEV
type conf\dev.csv | find /v "[product]" | find "[" | find /N "]" 1>%tmpdir%\dev.txt
CLS
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.选择\更换机型
ECHO.
ECHO.=--------------------------------------------------------------------=
ECHO.
ECHO.
ECHO.如果你有工具箱未适配的 中兴/努比亚/红魔 设备, 可以加反馈群联系群主适配.
ECHO.
ECHO.
for /f "tokens=1,3,4 delims=[]," %%a in (%tmpdir%\dev.txt) do (ECHO.[%%a] %%c  %%b& ECHO.)
ECHO.
call input choice
if "%choice%"=="" goto SELDEV
find "[%choice%][" "%tmpdir%\dev.txt" 1>nul 2>nul || goto SELDEV
ECHO.切换机型中. 请勿关闭窗口...
for /f "tokens=2 delims=[]," %%a in ('type %tmpdir%\dev.txt ^| find "[%choice%]["') do set product=%%a
call ztetoolbox confdevpre
call framework conf user.bat product %product%
call conf\dev-%product%.bat
goto MENU


:THEME
CLS
ECHOC {%c_a%}=--------------------------------------------------------------------={%c_i%}{\n}
ECHO.
ECHO.更改脚本主题
ECHO.
ECHOC {%c_a%}=--------------------------------------------------------------------={%c_i%}{\n}
ECHO.
ECHO.
ECHO.注意: 请勿在脚本运行时更换主题. 主题更换后重新打开脚本生效.
ECHO.
ECHO.
ECHO.1.默认
ECHO.2.经典
ECHO.3.乌班图
ECHO.4.抖音黑客
ECHO.5.流金
ECHO.6.DOS
ECHO.7.过年好
ECHO.
call input choice [1][2][3][4][5][6][7]
if "%choice%"=="1" set target=default
if "%choice%"=="2" set target=classic
if "%choice%"=="3" set target=ubuntu
if "%choice%"=="4" set target=douyinhacker
if "%choice%"=="5" set target=gold
if "%choice%"=="6" set target=dos
if "%choice%"=="7" set target=ChineseNewYear
::加载预览
call framework theme %target%
echo.@ECHO OFF>%tmpdir%\theme.bat
echo.mode con cols=50 lines=17 >>%tmpdir%\theme.bat
echo.cd ..>>%tmpdir%\theme.bat
echo.set path=%framework_workspace%;%framework_workspace%\tool\Win;%framework_workspace%\tool\Android;%path% >>%tmpdir%\theme.bat
echo.COLOR %c_i% >>%tmpdir%\theme.bat
echo.TITLE 主题预览: %target% >>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_i%}普通信息{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_w%}警告信息{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_e%}错误信息{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_s%}成功信息{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_h%}手动操作提示{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_a%}强调色{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.ECHOC {%c_we%}弱化色{%c_i%}{\n}>>%tmpdir%\theme.bat
echo.ECHO. >>%tmpdir%\theme.bat
echo.pause^>nul>>%tmpdir%\theme.bat
echo.EXIT>>%tmpdir%\theme.bat
call framework theme
start %tmpdir%\theme.bat
::加载预览完成
ECHO.
ECHO.已加载预览. 是否使用该主题
ECHO.1.使用   2.不使用
call input choice #[1][2]
if "%choice%"=="1" call framework conf user.bat framework_theme %target%& ECHOC {%c_i%}已更换主题, 重新打开脚本生效. {%c_h%}按任意键关闭脚本...{%c_i%}{\n}& call log %logger% I 更换主题为%target%& pause>nul & EXIT
if "%choice%"=="2" goto THEME






:FATAL
ECHO. & if exist tool\Win\ECHOC.exe (tool\Win\ECHOC {%c_e%}抱歉, 脚本遇到问题, 无法继续运行. 请查看日志. {%c_h%}按任意键退出...{%c_i%}{\n}& pause>nul & EXIT) else (ECHO.抱歉, 脚本遇到问题, 无法继续运行. 按任意键退出...& pause>nul & EXIT)
