::修改: n

::call info adb
::          fastboot
::          qcedl     端口号(数字或auto)  引导文件完整路径(可选,不填不发送)
::          par       分区名             [fail back](当找不到分区时的操作.可选.默认为fail)
::          disk      lun

@ECHO OFF
set args1=%1& set args2=%2& set args3=%3& set args4=%4& set args5=%5& set args6=%6& set args7=%7& set args8=%8& set args9=%9
goto %args1%




:QCEDL
SETLOCAL
set logger=info.bat-qcedl
set port=%args2%& set fh=%args3%
call log %logger% I 接收变量:port:%port%.fh:%fh%
:QCEDL-1
::如果端口号为auto或空则自动检查端口
if "%port%"=="auto" call chkdev qcedl 1>nul
if "%port%"=="auto" set port=%chkdev__port__qcedl%
if "%port%"=="" call chkdev qcedl 1>nul
if "%port%"=="" set port=%chkdev__port__qcedl%
::发送引导
if not "%fh%"=="" call write qcedlsendfh %port% %fh% auto
::读取设备信息
call log %logger% I 开始9008读取设备信息

set portstatus=firehose
set memtype=%storagetype%
if "%storagetype%"=="emmc" set secsize=512& set lunnum=1
if "%storagetype%"=="ufs" set secsize=4096& set lunnum=6
goto QCEDL-DONE

set portstatus=
set msmid=& set chipcodename=& set prefmemtype=
::& set oemid=& set vendor=
set memtype=& set secsize=& set lunnum=
::检查端口状态
::call log %logger% I 检查端口状态
::QSaharaServer.exe -p \\.\COM%port% -d 1>%tmpdir%\output.txt 2>&1
::type %tmpdir%\output.txt>>%logfile%
::set portstatus=
::for /f "tokens=2 delims=[]" %%a in ('type %tmpdir%\output.txt ^| find "[portstatus]"') do set portstatus=%%a
::if "%portstatus%"=="sahara" goto QCEDL-SAHARAMODE
::if "%portstatus%"=="firehose" goto QCEDL-FIREHOSEMODE
::ECHOC {%c_w%}端口状态未知. 以firehose模式继续...{%c_i%}{\n}& call log %logger% W 端口状态未知.以firehose模式继续
set portstatus=firehose
goto QCEDL-FIREHOSEMODE
:QCEDL-SAHARAMODE
call log %logger% I sahara模式读取设备信息
for /f "tokens=2 delims=[]" %%a in ('type %tmpdir%\output.txt ^| find "[msmid]"') do set msmid=%%a
::for /f "tokens=2 delims=[]" %%a in ('type %tmpdir%\output.txt ^| find "[oemid]"') do set oemid=%%a
busybox.exe sed "s/#.*//g" tool\Other\qualcomm_config.py>%tmpdir%\output.txt
if not "%msmid%"=="" (for /f "tokens=2 delims= " %%a in ('type %tmpdir%\output.txt ^| find /I " 0x%msmid%: "') do set chipcodename=%%a)
if not "%chipcodename%"=="" (set chipcodename=%chipcodename:~1,-2%)
if not "%chipcodename%"=="" (
    type %tmpdir%\output.txt | find /I " ""%chipcodename%"": ">%tmpdir%\output2.txt
    type %tmpdir%\output2.txt>>%logfile%
    find "ufs"    "%tmpdir%\output2.txt" 1>nul 2>nul && set prefmemtype=ufs
    find "emmc"   "%tmpdir%\output2.txt" 1>nul 2>nul && set prefmemtype=emmc
    find "spinor" "%tmpdir%\output2.txt" 1>nul 2>nul && set prefmemtype=spinor)
::if not "%oemid%"=="" (for /f "tokens=2 delims= " %%a in ('type %tmpdir%\output.txt ^| find /I " 0x%oemid%: "') do set vendor=%%a)
goto QCEDL-DONE
:QCEDL-FIREHOSEMODE
call log %logger% I firehose模式读取设备信息
call log %logger% I 判断存储类型和扇区大小
::  判断存储类型和扇区大小 (注意: 先获取ufs, 因为部分ufs设备获取emmc会掉端口)
::    尝试ufs回读
if exist %tmpdir%\tmp.bin del %tmpdir%\tmp.bin 1>>%logfile% 2>&1 || ECHOC {%c_e%}删除%tmpdir%\tmp.bin失败{%c_i%}{\n}&& call log %logger% F 删除%tmpdir%\tmp.bin失败&& goto FATAL
echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="0" label="PrimaryGPT" start_sector="0" num_partition_sectors="6" /^>^</data^>>%tmpdir%\tmp.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=ufs --sendxml=%tmpdir%\tmp.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || goto QCEDL-FIREHOSEMODE-2
if not exist %tmpdir%\tmp.bin goto QCEDL-FIREHOSEMODE-2
set var=
for /f "tokens=2 delims= " %%a in ('busybox.exe stat -t %tmpdir%\tmp.bin') do set var=%%a
if not "%var%"=="24576" goto QCEDL-FIREHOSEMODE-2
set memtype=ufs& set secsize=4096& goto QCEDL-FIREHOSEMODE-TESTLUNNUM
:QCEDL-FIREHOSEMODE-2
::    尝试emmc回读
if exist %tmpdir%\tmp.bin del %tmpdir%\tmp.bin 1>>%logfile% 2>&1 || ECHOC {%c_e%}删除%tmpdir%\tmp.bin失败{%c_i%}{\n}&& call log %logger% F 删除%tmpdir%\tmp.bin失败&& goto FATAL
echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="512" filename="tmp.bin" physical_partition_number="0" label="PrimaryGPT" start_sector="0" num_partition_sectors="34"/^>^</data^>>%tmpdir%\tmp.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=emmc --sendxml=%tmpdir%\tmp.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || goto QCEDL-FIREHOSEMODE-3
if not exist %tmpdir%\tmp.bin goto QCEDL-FIREHOSEMODE-3
set var=
for /f "tokens=2 delims= " %%a in ('busybox.exe stat -t %tmpdir%\tmp.bin') do set var=%%a
if not "%var%"=="17408" goto QCEDL-FIREHOSEMODE-3
set memtype=emmc& set secsize=512& set lunnum=1& goto QCEDL-DONE
:QCEDL-FIREHOSEMODE-3
::    尝试spinor回读
if exist %tmpdir%\tmp.bin del %tmpdir%\tmp.bin 1>>%logfile% 2>&1 || ECHOC {%c_e%}删除%tmpdir%\tmp.bin失败{%c_i%}{\n}&& call log %logger% F 删除%tmpdir%\tmp.bin失败&& goto FATAL
echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="0" label="PrimaryGPT" start_sector="0"  num_partition_sectors="6" /^>^</data^>>%tmpdir%\tmp.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=spinor --sendxml=%tmpdir%\tmp.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || goto QCEDL-FAILED
if not exist %tmpdir%\tmp.bin goto QCEDL-FAILED
set var=
for /f "tokens=2 delims= " %%a in ('busybox.exe stat -t %tmpdir%\tmp.bin') do set var=%%a
if not "%var%"=="24576" goto QCEDL-FAILED
set memtype=spinor& set secsize=4096& set lunnum=1& goto QCEDL-DONE
::  测试ufs可用lun
:QCEDL-FIREHOSEMODE-TESTLUNNUM
call log %logger% I 测试ufs可用lun
set num=0
:QCEDL-FIREHOSEMODE-TESTLUNNUM-1
if %num% GTR 8 ECHOC {%c_w%}当前设备测试可用lun为%num%. 常规lun应小于等于8. 请向开发者反馈.{%c_i%}{\n}& call log %logger% W 当前设备测试可用lun为%num%.常规lun应小于等于8
echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="gpt_main%num%.bin" physical_partition_number="%num%" label="PrimaryGPT" start_sector="0" num_partition_sectors="6" /^>^</data^>>%tmpdir%\tmp.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=ufs --sendxml=%tmpdir%\tmp.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || goto QCEDL-FIREHOSEMODE-TESTLUNNUM-2
gpttool.exe -p %tmpdir%\gpt_main%num%.bin -f print:default:#inseltgf:sector:10 1>>%logfile% 2>&1 || goto QCEDL-FIREHOSEMODE-TESTLUNNUM-2
set /a num+=1& goto QCEDL-FIREHOSEMODE-TESTLUNNUM-1
:QCEDL-FIREHOSEMODE-TESTLUNNUM-2
if %num% EQU 0 ECHOC {%c_e%}当前设备测试可用lun为%num%. 这可能是由于分区表错误. 请尝试手动指定存储类型和lun, 或向开发者反馈.{%c_i%}{\n}& call log %logger% E 当前设备测试可用lun为%num%& goto QCEDL-FAILED
if %num% LSS 6 ECHOC {%c_w%}当前设备测试可用lun为%num%. 常规lun应大于等于6. 请向开发者反馈.{%c_i%}{\n}& call log %logger% W 当前设备测试可用lun为%num%.常规lun应大于等于6
set lunnum=%num%& goto QCEDL-DONE
:QCEDL-DONE
call log %logger% I 9008读取到设备信息:端口状态:%portstatus%.msmid:%msmid%.处理器代号:%chipcodename%.首选存储类型:%prefmemtype%.存储类型:%memtype%.扇区大小:%secsize%.lun:%lunnum%
ENDLOCAL & set info__qcedl__portstatus=%portstatus%& set info__qcedl__msmid=%msmid%& set info__qcedl__chipcodename=%chipcodename%& set info__qcedl__prefmemtype=%prefmemtype%& set info__qcedl__memtype=%memtype%& set info__qcedl__secsize=%secsize%& set info__qcedl__lunnum=%lunnum%
goto :eof
:QCEDL-FAILED
ECHOC {%c_e%}9008读取设备信息失败. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 9008读取设备信息失败.当前结果:存储类型:%memtype%.扇区大小:%secsize%.lun:%lunnum%& pause>nul & ECHO.重试... & goto QCEDL-1


:ADB
SETLOCAL
set logger=info.bat-adb
call log %logger% I 开始读取ADB设备信息
:ADB-1
set product=
for /f %%a in ('adb.exe shell getprop ro.product.device') do set product=%%a
if "%product%"=="" call log %logger% E ro.product.device读取失败& ECHOC {%c_e%}ro.product.device读取失败. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & ECHO.重试... & goto ADB-1
set androidver=
for /f %%a in ('adb.exe shell getprop ro.build.version.release') do set androidver=%%a
if "%androidver%"=="" call log %logger% E ro.build.version.release读取失败& ECHOC {%c_e%}ro.build.version.release读取失败. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & ECHO.重试... & goto ADB-1
set sdkver=
for /f %%a in ('adb.exe shell getprop ro.build.version.sdk') do set sdkver=%%a
if "%sdkver%"=="" call log %logger% E ro.build.version.sdk读取失败& ECHOC {%c_e%}ro.build.version.sdk读取失败. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & ECHO.重试... & goto ADB-1
call log %logger% I 读取到ADB设备信息:product:%product%.androidver:%androidver%.sdkver:%sdkver%
ENDLOCAL & set info__adb__product=%product%& set info__adb__androidver=%androidver%& set info__adb__sdkver=%sdkver%
goto :eof


:FASTBOOT
SETLOCAL
set logger=info.bat-fastboot
call log %logger% I 开始读取Fastboot设备信息
:FASTBOOT-1
set product=
for /f "tokens=2 delims=: " %%a in ('fastboot getvar product 2^>^&1^| find "product"') do set product=%%a
if "%product%"=="" call log %logger% E product读取失败& ECHOC {%c_e%}product读取失败. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & ECHO.重试... & goto FASTBOOT-1
set unlocked=
for /f "tokens=2 delims=: " %%a in ('fastboot getvar unlocked 2^>^&1^| find "unlocked"') do set unlocked=%%a
if "%unlocked%"=="" call log %logger% E unlocked读取失败& ECHOC {%c_e%}unlocked读取失败. {%c_h%}按任意键重试...{%c_i%}{\n}& pause>nul & ECHO.重试... & goto FASTBOOT-1
call log %logger% I 读取到Fastboot设备信息:product:%product%.unlocked:%unlocked%
ENDLOCAL & set info__fastboot__product=%product%& set info__fastboot__unlocked=%unlocked%
goto :eof
::附:摩托罗拉设备判断解锁的方法如下: fastboot getvar securestate 2>&1| find "flashing_unlocked" 1>nul 2>nul && set unlocked=yes


:PAR
SETLOCAL
set logger=info.bat-par
set parname=%args2%& set ifparnotexist=%args3%
if "%ifparnotexist%"=="" set ifparnotexist=fail
call log %logger% I 接收变量:parname:%parname%.ifparnotexist:%ifparnotexist%
:PAR-1
call chkdev all 1>nul
if not "%chkdev__mode%"=="system" (if not "%chkdev__mode%"=="recovery" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误, 只支持在系统, Recovery或9008获取分区信息. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 模式错误:%chkdev__mode%.应进入系统或Recovery或9008模式& pause>nul & ECHO.重试... & goto PAR-1))
::检查端口状态
::if "%chkdev__mode%"=="qcedl" (
::    QSaharaServer.exe -p \\.\COM%chkdev__port% -d | find "[portstatus]firehose" 1>nul 2>nul || ECHOC {%c_e%}端口不在firehose模式. 请发送引导并配置端口后再试. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 端口不在firehose模式&& pause>nul && ECHO.重试... && goto PAR-1)
call log %logger% I 开始读取分区信息
::emmc
:PAR-2
set disktype=emmc& set disklun=0
call :paranddisk-read512kb
if "%result%"=="y" call :par-getinfo & goto PAR-DONE
::ufs
set disktype=ufs& set disklun=0
:PAR-3
if "%disklun%"=="8" goto PAR-4
call :paranddisk-read512kb
if "%result%"=="y" call :par-getinfo
if "%result%"=="y" (if "%parexist%"=="y" goto PAR-DONE)
set /a disklun+=1& goto PAR-3
::spinor  spinor的数据是AI搜索得来, 未经实机验证
:PAR-4
set disktype=spinor& set disklun=0
call :paranddisk-read512kb
if "%result%"=="y" call :par-getinfo
if "%result%"=="n" set parexist=n
goto PAR-DONE
:PAR-DONE
if "%parexist%"=="n" (
    if "%ifparnotexist%"=="fail" ECHOC {%c_e%}找不到分区:%parname%. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 找不到分区:%parname%& pause>nul & ECHO.重试... & goto PAR-1
    if "%ifparnotexist%"=="back" call log %logger% I 读取分区信息完成.找不到分区:%parname%)
if "%parexist%"=="y" call log %logger% I 读取分区信息完成:parexist:%parexist%.diskpath:%diskpath%.parnum:%parnum%.parpath:%parpath%.partype:%partype%.parstart:%parstart%.parend:%parend%.parsize:%parsize%.disksecsize:%disksecsize%.disktype:%disktype%.parguid:%parguid%.parflag:%parflag%.disklun:%disklun%
ENDLOCAL & set info__par__exist=%parexist%& set info__par__diskpath=%diskpath%& set info__par__num=%parnum%& set info__par__path=%parpath%& set info__par__type=%partype%& set info__par__start=%parstart%& set info__par__end=%parend%& set info__par__size=%parsize%& set info__par__disksecsize=%disksecsize%& set info__par__disktype=%disktype%& set info__par__parguid=%parguid%& set info__par__parflag=%parflag%& set info__par__disklun=%disklun%
goto :eof
::解析gpt获得信息. 目标: 获得分区信息
::使用变量: parname
::使用文件: %tmpdir%\tmp.bin
::使用: call :par-getinfo
::返回: parexist disksecsize parnum parstart parend parsize partype parguid parflag parpath
:par-getinfo
set parexist=n& set disksecsize=& set parpath=& set parnum=& set parstart=& set parend=& set parsize=& set partype=& set parguid=& set parflag=
gpttool.exe -p %tmpdir%\tmp.bin -f print:default:#inseltgf:b:10 -o %tmpdir%\output2.txt 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& goto :eof
type %tmpdir%\output.txt>>%logfile%
::  parexist
find " %parname% " "%tmpdir%\output2.txt" 1>nul 2>nul || goto :eof
set parexist=y
::  disksecsize
for /f "tokens=2 delims= " %%a in ('type %tmpdir%\output.txt ^| find "[BasicInfo]Disk_SecSize_b_Dec"') do set disksecsize=%%a
set var=n
if "%disktype%"=="emmc" (if "%disksecsize%"=="512" set var=y)
if "%disktype%"=="ufs" (if "%disksecsize%"=="4096" set var=y)
if "%disktype%"=="spinor" (if "%disksecsize%"=="4096" set var=y)
if "%var%"=="n" ECHOC {%c_e%}不支持的设备:存储类型:%disktype%.扇区大小:%disksecsize%{%c_i%}{\n}& call log %logger% F 不支持的设备:存储类型:%disktype%.扇区大小:%disksecsize%& goto FATAL
::  parnum等
for /f "tokens=2,3,4,5,6,7,8,9 delims= " %%a in ('type %tmpdir%\output2.txt ^| find " %parname% "') do (set parnum=%%a& set parname_forchk=%%b& set parstart=%%c& set parend=%%d& set parsize=%%e& set partype=%%f& set parguid=%%g& set parflag=%%h)
if not "%parname_forchk%"=="%parname%" ECHOC {%c_e%}查找分区失败.目标分区名:%parname%.读取到的分区名:%parname_forchk%{%c_i%}{\n}& call log %logger% F 查找分区失败.目标分区名:%parname%.读取到的分区名:%parname_forchk%& goto FATAL
::  parpath
if "%disktype%"=="emmc"   set parpath=%diskpath%p%parnum%
if "%disktype%"=="ufs"    set parpath=%diskpath%%parnum%
if "%disktype%"=="spinor" set parpath=%diskpath%%parnum%
goto :eof


:DISK
SETLOCAL
set logger=info.bat-disk
set disklun=%args2%
call log %logger% I 接收变量:disklun:%disklun%
:DISK-1
call chkdev all 1>nul
if not "%chkdev__mode%"=="system" (if not "%chkdev__mode%"=="recovery" (if not "%chkdev__mode%"=="qcedl" ECHOC {%c_e%}设备模式错误, 只支持在系统, Recovery或9008获取分区路径. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 模式错误:%chkdev__mode%.应进入系统或Recovery或9008模式& pause>nul & ECHO.重试... & goto DISK-1))
::检查端口状态
::if "%chkdev__mode%"=="qcedl" (
::    QSaharaServer.exe -p \\.\COM%port% -d | find "[portstatus]firehose" 1>nul 2>nul || ECHOC {%c_e%}端口不在firehose模式. 请发送引导并配置端口后再试. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 端口不在firehose模式&& pause>nul && ECHO.重试... && goto DISK-1)
call log %logger% I 开始读取存储信息
::获取存储类型
set disktype=ufs& set disklun=%disklun%
call :paranddisk-read512kb
if "%result%"=="y" goto DISK-2
set disktype=emmc& set disklun=%disklun%
call :paranddisk-read512kb
if "%result%"=="y" goto DISK-2
set disktype=spinor& set disklun=%disklun%
call :paranddisk-read512kb
if "%result%"=="y" goto DISK-2
if "%var%"=="n" ECHOC {%c_e%}检查存储类型失败. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 检查存储类型失败& pause>nul & ECHO.重试... & goto DISK-1
:DISK-2
::获取信息
gpttool.exe -p %tmpdir%\tmp.bin -f print:default:#in:b:10 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}读取分区表信息失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 读取分区表信息失败&& pause>nul && ECHO.重试... && goto DISK-1
type %tmpdir%\output.txt>>%logfile%
::  disksecsize
set disksecsize=
for /f "tokens=2 delims= " %%a in ('type %tmpdir%\output.txt ^| find "[BasicInfo]Disk_SecSize_b_Dec"') do set disksecsize=%%a
set var=n
if "%disktype%"=="emmc" (if "%disksecsize%"=="512" set var=y)
if "%disktype%"=="ufs" (if "%disksecsize%"=="4096" set var=y)
if "%disktype%"=="spinor" (if "%disksecsize%"=="4096" set var=y)
if "%var%"=="n" ECHOC {%c_e%}不支持的设备:存储类型:%disktype%.扇区大小:%disksecsize%{%c_i%}{\n}& call log %logger% F 不支持的设备:存储类型:%disktype%.扇区大小:%disksecsize%& goto FATAL
::  maxparnum
set maxparnum=
for /f "tokens=2 delims= " %%a in ('type %tmpdir%\output.txt ^| find "[BasicInfo]ParEntry_Num_Defined"') do set maxparnum=%%a
if "%maxparnum%"=="" ECHOC {%c_e%}获取最大分区数失败. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 获取最大分区数失败& pause>nul & ECHO.重试... & goto DISK-1
call log %logger% I 读取存储信息完成:disktype:%disktype%.disksecsize:%disksecsize%.maxparnum:%maxparnum%
ENDLOCAL & set info__disk__type=%disktype%& set info__disk__secsize=%disksecsize%& set info__disk__maxparnum=%maxparnum%
goto :eof


::读取gpt. PAR和DISK功能通用. 目标: 获得 %tmpdir%\tmp.bin
::使用变量: disktype disklun chkdev__mode chkdev__port__qcedl
::使用:
::  set disktype=xxx& set disklun=xxx
::  call :paranddisk-read512kb
::返回: result diskpath
:paranddisk-read512kb
set var=& set diskpath=
if "%disktype%"=="emmc" set var=/dev/block/mmcblk%disklun%
if "%disktype%"=="ufs" (if "%disklun%"=="0" set var=/dev/block/sda)
if "%disktype%"=="ufs" (if "%disklun%"=="1" set var=/dev/block/sdb)
if "%disktype%"=="ufs" (if "%disklun%"=="2" set var=/dev/block/sdc)
if "%disktype%"=="ufs" (if "%disklun%"=="3" set var=/dev/block/sdd)
if "%disktype%"=="ufs" (if "%disklun%"=="4" set var=/dev/block/sde)
if "%disktype%"=="ufs" (if "%disklun%"=="5" set var=/dev/block/sdf)
if "%disktype%"=="ufs" (if "%disklun%"=="6" set var=/dev/block/sdg)
if "%disktype%"=="ufs" (if "%disklun%"=="7" set var=/dev/block/sdh)
if "%disktype%"=="spinor" set var=/dev/mtdblock
goto paranddisk-read512kb-%chkdev__mode%
:paranddisk-read512kb-system
echo.su>%tmpdir%\cmd.txt& echo.dd if=%var% of=/sdcard/bff_tmp.bin bs=524288 count=1 >>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
call read adbpull /sdcard/bff_tmp.bin %tmpdir%\tmp.bin noprompt
set result=y& set diskpath=%var%& goto :eof
:paranddisk-read512kb-recovery
echo.dd if=%var% of=/bff_tmp.bin bs=524288 count=1 >%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
call read adbpull /bff_tmp.bin %tmpdir%\tmp.bin noprompt
set result=y& set diskpath=%var%& goto :eof
:paranddisk-read512kb-qcedl
if "%disktype%"=="emmc" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="512" filename="tmp.bin" physical_partition_number="%disklun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="1024"/^>^</data^>>%tmpdir%\cmd.xml
if "%disktype%"=="ufs" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%disklun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="128"/^>^</data^>>%tmpdir%\cmd.xml
if "%disktype%"=="spinor" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%disklun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="128"/^>^</data^>>%tmpdir%\cmd.xml
fh_loader.exe --port=\\.\COM%chkdev__port__qcedl% --memoryname=%disktype% --sendxml=%tmpdir%\cmd.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& set diskpath=%var%& goto :eof













:FATAL
ECHO. & if exist tool\Win\ECHOC.exe (tool\Win\ECHOC {%c_e%}抱歉, 脚本遇到问题, 无法继续运行. 请查看日志. {%c_h%}按任意键退出...{%c_i%}{\n}& pause>nul & EXIT) else (ECHO.抱歉, 脚本遇到问题, 无法继续运行. 按任意键退出...& pause>nul & EXIT)
