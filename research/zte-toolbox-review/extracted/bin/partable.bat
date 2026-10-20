::修改: n

::              args1     args2                                  args3                   args4    args5                       args6                                                   args7                                 args8                       args9
::call partable readgpt   [system recovery qcedl auto]           [ufs emmc spinor auto]  目标lun  [gptmain gptbackup gptboth] 文件保存路径                                              [notice noprompt]                     仅qcedl填:端口号[数字 auto]   仅qcedl填:引导文件路径(可选,不填不发送)
::              writegpt  [system recovery qcedl fastboot auto]  [ufs emmc spinor auto]  目标lun  文件路径                     仅qcedl填:端口号(数字或auto)                               仅qcedl填:引导文件路径(可选,不填不发送)
::              mkpar     [system recovery qcedl auto]           [ufs emmc spinor auto]  目标lun  分区名                       start                                                   [end:xxx或size:xxx]                    类型                        标签[default 0000000000000000]
::              rmpar     [system recovery qcedl auto]           [ufs emmc spinor auto]  目标lun  [name:x或index:x或guid:x]
::              editpar   [system recovery qcedl auto]           [ufs emmc spinor auto]  目标lun  [name:x或index:x或guid:x]    [index:x或type:x或guid:x或start:x或end:x或flag:x或name:x]
::              mvpar     [system recovery qcedl auto]           [ufs emmc spinor auto]  目标lun  [name:x或index:x或guid:x]    移动方向[up down]                                        移动扇区数[值 auto]

@ECHO OFF
set args1=%1& set args2=%2& set args3=%3& set args4=%4& set args5=%5& set args6=%6& set args7=%7& set args8=%8& set args9=%9
goto %args1%





:MVPAR
SETLOCAL
set logger=partable.bat-mvpar
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set basisinfo=%args5%& set direction=%args6%& set length=%args7%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.basisinfo:%basisinfo%.direction:%direction%.length:%length%
:MVPAR-1
call log %logger% I 开始移动分区
::编辑分区通用准备工作
call :editpar-pre
::确定 length_sec
call calc b2sec length_sec nodec %length% %secsize%
::回读分区表
call partable readgpt %mode_arg% %storagetype% %lun% gptmain %tmpdir%\tmp.bin noprompt auto
::修改分区表
call log %logger% I 开始修改分区表文件
gpttool.exe -p %tmpdir%\tmp.bin -f mvpar:%basisinfo%:%direction%:%length_sec% 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}修改分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 修改分区表文件失败&& pause>nul && ECHO.重试... && goto MVPAR-1
type %tmpdir%\output.txt>>%logfile%
::写入分区表
call partable writegpt %mode_arg% %storagetype% %lun% %tmpdir%\tmp.bin auto
::完成
call log %logger% I 移动分区完成
ENDLOCAL
goto :eof


:EDITPAR
SETLOCAL
set logger=partable.bat-editpar
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set basisinfo=%args5%& set attriinfo=%args6%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.basisinfo:%basisinfo%.attriinfo:%attriinfo%
:EDITPAR-1
call log %logger% I 开始编辑分区
::编辑分区通用准备工作
call :editpar-pre
::回读分区表
call partable readgpt %mode_arg% %storagetype% %lun% gptmain %tmpdir%\tmp.bin noprompt auto
::修改分区表
call log %logger% I 开始修改分区表文件
gpttool.exe -p %tmpdir%\tmp.bin -f editpar:%basisinfo%:%attriinfo% 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}修改分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 修改分区表文件失败&& pause>nul && ECHO.重试... && goto EDITPAR-1
type %tmpdir%\output.txt>>%logfile%
::写入分区表
call partable writegpt %mode_arg% %storagetype% %lun% %tmpdir%\tmp.bin auto
::完成
call log %logger% I 编辑分区完成
ENDLOCAL
goto :eof


:RMPAR
SETLOCAL
set logger=partable.bat-rmpar
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set basisinfo=%args5%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.basisinfo:%basisinfo%
:RMPAR-1
call log %logger% I 开始删除分区
::编辑分区通用准备工作
call :editpar-pre
::回读分区表
call partable readgpt %mode_arg% %storagetype% %lun% gptmain %tmpdir%\tmp.bin noprompt auto
::修改分区表
call log %logger% I 开始修改分区表文件
gpttool.exe -p %tmpdir%\tmp.bin -f rmpar:%basisinfo% 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}修改分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 修改分区表文件失败&& pause>nul && ECHO.重试... && goto RMPAR-1
type %tmpdir%\output.txt>>%logfile%
::写入分区表
call partable writegpt %mode_arg% %storagetype% %lun% %tmpdir%\tmp.bin auto
::完成
call log %logger% I 删除分区完成
ENDLOCAL
goto :eof


:MKPAR
SETLOCAL
set logger=partable.bat-mkpar
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set parname=%args5%& set parstart=%args6%& set parendorsize=%args7%& set partype=%args8%& set parflag=%args9%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.parname:%parname%.parstart:%parstart%.parendorsize:%parendorsize%.partype:%partype%.parflag:%parflag%
:MKPAR-1
call log %logger% I 开始新建分区
::编辑分区通用准备工作
call :editpar-pre
::确定 parstart_sec
call calc b2sec parstart_sec nodec %parstart% %secsize%
::确定 parend_sec
set var1=& set var2=
for /f "tokens=1,2 delims=: " %%a in ('echo.%parendorsize%') do (set var1=%%a& set var2=%%b)
if "%var1%"=="end" call calc b2sec parend_sec nodec %var2% %secsize%
if "%var1%"=="size" call calc b2sec parsize_sec nodec %var2% %secsize%
if "%var1%"=="size" call calc p parstartnext_sec nodec %parstart_sec% %parsize_sec%
if "%var1%"=="size" call calc s parend_sec nodec %parstartnext_sec% 1
::回读分区表
call partable readgpt %mode_arg% %storagetype% %lun% gptmain %tmpdir%\tmp.bin noprompt auto
::修改分区表
call log %logger% I 开始修改分区表文件
gpttool.exe -p %tmpdir%\tmp.bin -f mkpar:auto:%parname%:%parstart_sec%:%parend_sec%:%partype%:%parflag% 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}修改分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 修改分区表文件失败&& pause>nul && ECHO.重试... && goto MKPAR-1
type %tmpdir%\output.txt>>%logfile%
::写入分区表
call partable writegpt %mode_arg% %storagetype% %lun% %tmpdir%\tmp.bin auto
::完成
call log %logger% I 新建分区完成
ENDLOCAL
goto :eof


::编辑分区通用准备工作
::call :editpar-pre
:editpar-pre
::确定 storagetype
if not "%storagetype_arg%"=="auto" set storagetype=%storagetype_arg%
if "%storagetype_arg%"=="auto" call info disk %lun%
if "%storagetype_arg%"=="auto" set storagetype=%info__disk__type%
::确定 secsize
if "%storagetype%"=="emmc" set secsize=512
if "%storagetype%"=="ufs" set secsize=4096
if "%storagetype%"=="spinor" set secsize=4096
goto :eof


:WRITEGPT
SETLOCAL
set logger=partable.bat-writegpt
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set filepath=%args5%& set port_arg=%args6%& set fh=%args7%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.filepath:%filepath%.port_arg:%port_arg%.fh:%fh%
:WRITEGPT-1
call log %logger% I 开始写入分区表文件
::文件是否存在
if not exist %filepath% ECHOC {%c_e%}找不到文件: %filepath%. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 找不到文件:%filepath%& pause>nul & ECHO.重试... & goto WRITEGPT-1
::获取文件大小
set filesize=
for /f "tokens=2 delims= " %%a in ('busybox.exe stat -t %filepath%') do set filesize=%%a
if "%filesize%"=="" ECHOC {%c_e%}获取%filepath%大小失败{%c_i%}{\n}& call log %logger% F 获取%filepath%大小失败 & goto FATAL
call calc d filesize_sec_512  nodec-intp1 %filesize% 512
call calc d filesize_sec_4096 nodec-intp1 %filesize% 4096
::根据需要检查设备连接
if "%mode_arg%"=="auto" call chkdev all 1>nul & goto WRITEGPT-2
if "%mode%"=="qcedl" (if "%port_arg%"=="auto" call chkdev qcedl 1>nul & goto WRITEGPT-2)
:WRITEGPT-2
::确定设备模式
if not "%mode_arg%"=="auto" set mode=%mode_arg%
if "%mode_arg%"=="auto" set mode=%chkdev__mode%
if not "%mode%"=="system" (if not "%mode%"=="recovery" (if not "%mode%"=="qcedl" (if not "%mode%"=="fastboot" ECHOC {%c_e%}模式错误, 请进入系统, Recovery, Fastboot或9008模式. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 模式错误.请进入系统或Recovery或Fastboot或9008模式& pause>nul & ECHO.重试... & goto WRITEGPT-1)))
::确定端口
if "%mode%"=="qcedl" (
    if not "%port_arg%"=="auto" set port=%port_arg%
    if "%port_arg%"=="auto" set port=%chkdev__port__qcedl%)
::格式化分区表文件
if not "%chkdev__mode%"=="fastboot" (set var=gptmain) else (set var=gptboth)
gpttool.exe -p %filepath% -f convert:%var% -o %tmpdir%\tmp.bin 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}格式化分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 格式化分区表文件失败&& pause>nul && ECHO.重试... && goto WRITEGPT-1
type %tmpdir%\output.txt>>%logfile%
set filepath_formatted=%tmpdir%\tmp.bin
::发送引导
if "%mode%"=="qcedl" (if not "%fh%"=="" call write qcedlsendfh %port% %fh% auto)
::写入文件
if "%storagetype_arg%"=="auto" (goto WRITEGPT-3) else (goto WRITEGPT-4)
::  自动识别存储类型
:WRITEGPT-3
set storagetype=ufs
call :writegpt-write
if "%result%"=="y" goto WRITEGPT-5
set storagetype=emmc
call :writegpt-write
if "%result%"=="y" goto WRITEGPT-5
set storagetype=spinor
call :writegpt-write
if "%result%"=="y" goto WRITEGPT-5
goto WRITEGPT-FAILED
::  指定存储类型
:WRITEGPT-4
set storagetype=%storagetype_arg%
call :writegpt-write
if "%result%"=="y" (goto WRITEGPT-5) else (goto WRITEGPT-FAILED)
::完成
:WRITEGPT-5
call log %logger% I 写入分区表文件完成
ENDLOCAL
goto :eof
:WRITEGPT-FAILED
ECHOC {%c_e%}写入分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 写入分区表文件失败& pause>nul & ECHO.重试... & goto WRITEGPT-1
::写入分区表文件. 目标: 写入 %filepath_formatted%
::使用变量: storagetype lun mode port filesize
::使用:
::  set storagetype=xxx
::  call :writegpt-write
::返回: result
:writegpt-write
set var=
if "%storagetype%"=="emmc" set var=/dev/block/mmcblk%lun%
if "%storagetype%"=="ufs" (if "%lun%"=="0" set var=/dev/block/sda)
if "%storagetype%"=="ufs" (if "%lun%"=="1" set var=/dev/block/sdb)
if "%storagetype%"=="ufs" (if "%lun%"=="2" set var=/dev/block/sdc)
if "%storagetype%"=="ufs" (if "%lun%"=="3" set var=/dev/block/sdd)
if "%storagetype%"=="ufs" (if "%lun%"=="4" set var=/dev/block/sde)
if "%storagetype%"=="ufs" (if "%lun%"=="5" set var=/dev/block/sdf)
if "%storagetype%"=="ufs" (if "%lun%"=="6" set var=/dev/block/sdg)
if "%storagetype%"=="ufs" (if "%lun%"=="7" set var=/dev/block/sdh)
if "%storagetype%"=="spinor" set var=/dev/mtdblock
goto writegpt-write-%mode%
:writegpt-write-system
call write adbpush %filepath_formatted% bff_tmp.bin common
echo.su>%tmpdir%\cmd.txt& echo.dd if=%write__adbpush__filepath% of=%var% bs=%filesize% count=1 >>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& goto :eof
:writegpt-write-recovery
call write adbpush %filepath_formatted% bff_tmp.bin common
echo.dd if=%write__adbpush__filepath% of=%var% bs=%filesize% count=1 >%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& goto :eof
:writegpt-write-fastboot
fastboot.exe flash partition:%lun% %filepath_formatted% 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& goto :eof
:writegpt-write-qcedl
if "%storagetype%"=="emmc" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="512" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="%filesize_sec_512%"/^>^</data^>>%tmpdir%\cmd.xml
if "%storagetype%"=="ufs" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="%filesize_sec_4096%"/^>^</data^>>%tmpdir%\cmd.xml
if "%storagetype%"=="spinor" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="%filesize_sec_4096%"/^>^</data^>>%tmpdir%\cmd.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=%storagetype% --search_path=%tmpdir% --sendxml=%tmpdir%\cmd.xml --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& goto :eof


:READGPT
SETLOCAL
set logger=partable.bat-readgpt
set mode_arg=%args2%& set storagetype_arg=%args3%& set lun=%args4%& set outputtype=%args5%& set outputpath=%args6%& set fileexistsfunc=%args7%& set port_arg=%args8%& set fh=%args9%
call log %logger% I 接收变量:mode_arg:%mode_arg%.storagetype_arg:%storagetype_arg%.lun:%lun%.outputtype:%outputtype%.outputpath:%outputpath%.fileexistsfunc:%fileexistsfunc%.port_arg:%port_arg%.fh:%fh%
:READGPT-1
call log %logger% I 开始读取分区表文件
::文件已存在的操作
if exist %outputpath% (if not "%fileexistsfunc%"=="noprompt" ECHOC {%c_w%}已存在%outputpath%, 继续将覆盖此文件. {%c_h%}按任意键继续...{%c_i%}{\n}& call log %logger% W 已存在%outputpath%.继续将覆盖此文件& pause>nul & ECHO.继续...)
::根据需要检查设备连接
if "%mode_arg%"=="auto" call chkdev all 1>nul & goto READGPT-2
if "%mode%"=="qcedl" (if "%port_arg%"=="auto" call chkdev qcedl 1>nul & goto READGPT-2)
:READGPT-2
::确定设备模式
if not "%mode_arg%"=="auto" set mode=%mode_arg%
if "%mode_arg%"=="auto" set mode=%chkdev__mode%
if not "%mode%"=="system" (if not "%mode%"=="recovery" (if not "%mode%"=="qcedl" ECHOC {%c_e%}模式错误, 请进入系统, Recovery或9008模式. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 模式错误.请进入系统或Recovery或9008模式& pause>nul & ECHO.重试... & goto READGPT-1))
::确定端口
if "%mode%"=="qcedl" (
    if not "%port_arg%"=="auto" set port=%port_arg%
    if "%port_arg%"=="auto" set port=%chkdev__port__qcedl%)
::发送引导
if "%mode%"=="qcedl" (if not "%fh%"=="" call write qcedlsendfh %port% %fh% auto)
::读取前512KB
if "%storagetype_arg%"=="auto" (goto READGPT-3) else (goto READGPT-4)
::  自动识别存储类型
:READGPT-3
set storagetype=ufs
call :readgpt-read512kb
if "%result%"=="y" goto READGPT-5
set storagetype=emmc
call :readgpt-read512kb
if "%result%"=="y" goto READGPT-5
set storagetype=spinor
call :readgpt-read512kb
if "%result%"=="y" goto READGPT-5
goto READGPT-FAILED
::  指定存储类型
:READGPT-4
set storagetype=%storagetype_arg%
call :readgpt-read512kb
if "%result%"=="y" (goto READGPT-5) else (goto READGPT-FAILED)
::格式化分区表文件
:READGPT-5
gpttool.exe -p %tmpdir%\tmp.bin -f convert:%outputtype% -o %outputpath% 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile%&& ECHOC {%c_e%}格式化分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}&& call log %logger% E 格式化分区表文件失败&& pause>nul && ECHO.重试... && goto READGPT-1
type %tmpdir%\output.txt>>%logfile%
call log %logger% I 读取分区表文件完成
ENDLOCAL
goto :eof
:READGPT-FAILED
ECHOC {%c_e%}读取分区表文件失败. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 读取分区表文件失败& pause>nul & ECHO.重试... & goto READGPT-1
::读取前512KB. 目标: 获得 %tmpdir%\tmp.bin
::使用变量: storagetype lun mode port
::使用:
::  set storagetype=xxx
::  call :readgpt-read512kb
::返回: result
:readgpt-read512kb
set var=& set storagepath=
if "%storagetype%"=="emmc" set var=/dev/block/mmcblk%lun%
if "%storagetype%"=="ufs" (if "%lun%"=="0" set var=/dev/block/sda)
if "%storagetype%"=="ufs" (if "%lun%"=="1" set var=/dev/block/sdb)
if "%storagetype%"=="ufs" (if "%lun%"=="2" set var=/dev/block/sdc)
if "%storagetype%"=="ufs" (if "%lun%"=="3" set var=/dev/block/sdd)
if "%storagetype%"=="ufs" (if "%lun%"=="4" set var=/dev/block/sde)
if "%storagetype%"=="ufs" (if "%lun%"=="5" set var=/dev/block/sdf)
if "%storagetype%"=="ufs" (if "%lun%"=="6" set var=/dev/block/sdg)
if "%storagetype%"=="ufs" (if "%lun%"=="7" set var=/dev/block/sdh)
if "%storagetype%"=="spinor" set var=/dev/mtdblock
goto readgpt-read512kb-%mode%
:readgpt-read512kb-system
echo.su>%tmpdir%\cmd.txt& echo.dd if=%var% of=/sdcard/bff_tmp.bin bs=524288 count=1 >>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
call read adbpull /sdcard/bff_tmp.bin %tmpdir%\tmp.bin noprompt
set result=y& set storagepath=%var%& goto :eof
:readgpt-read512kb-recovery
echo.dd if=%var% of=/bff_tmp.bin bs=524288 count=1 >%tmpdir%\cmd.txt& echo.exit>>%tmpdir%\cmd.txt
adb.exe shell < %tmpdir%\cmd.txt 1>>%logfile% 2>&1 || set result=n&& goto :eof
call read adbpull /bff_tmp.bin %tmpdir%\tmp.bin noprompt
set result=y& set storagepath=%var%& goto :eof
:readgpt-read512kb-qcedl
if "%storagetype%"=="emmc" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="512" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="1024"/^>^</data^>>%tmpdir%\cmd.xml
if "%storagetype%"=="ufs" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="128"/^>^</data^>>%tmpdir%\cmd.xml
if "%storagetype%"=="spinor" echo.^<?xml version="1.0" ?^>^<data^>^<program SECTOR_SIZE_IN_BYTES="4096" filename="tmp.bin" physical_partition_number="%lun%" label="PrimaryGPT" start_sector="0" num_partition_sectors="128"/^>^</data^>>%tmpdir%\cmd.xml
fh_loader.exe --port=\\.\COM%port% --memoryname=%storagetype% --sendxml=%tmpdir%\cmd.xml --convertprogram2read --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || set result=n&& goto :eof
set result=y& set storagepath=%var%& goto :eof





















:FATAL
ECHO. & if exist tool\Win\ECHOC.exe (tool\Win\ECHOC {%c_e%}抱歉, 脚本遇到问题, 无法继续运行. 请查看日志. {%c_h%}按任意键退出...{%c_i%}{\n}& pause>nul & EXIT) else (ECHO.抱歉, 脚本遇到问题, 无法继续运行. 按任意键退出...& pause>nul & EXIT)


