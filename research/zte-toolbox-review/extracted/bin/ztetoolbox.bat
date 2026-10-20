::call ztetoolbox confdevpre
::                confeditionpre
::                edlsetbootablestoragedrive  端口号      存储类型[auto emmc ufs spinor]   引导文件完整路径(可选,不填不发送)
::                edlreadall                  端口号      img存放文件夹                    引导文件完整路径(可选,不填不发送)
::                chkproduct                  读取的代号


@ECHO OFF
set args1=%1& set args2=%2& set args3=%3& set args4=%4& set args5=%5& set args6=%6& set args7=%7& set args8=%8& set args9=%9
goto %args1%




:CHKPRODUCT
SETLOCAL
set logger=ztetoolbox.bat-chkproduct
::接收变量
set product_read=%args2%
call log %logger% I 接收变量:product_read:%product_read%
:CHKPRODUCT-1
if "%product_read%"=="%product%" goto CHKPRODUCT-DONE
if "%product%"=="P855A01" (
    if "%product_read%"=="P855A02" goto CHKPRODUCT-DONE
    if "%product_read%"=="P855A21" goto CHKPRODUCT-DONE)
if "%product%"=="P875A02" (
    if "%product_read%"=="P875A12" goto CHKPRODUCT-DONE
    if "%product_read%"=="P875N02" goto CHKPRODUCT-DONE
    if "%product_read%"=="NX666J" goto CHKPRODUCT-DONE)
if "%product%"=="P725A12" (
    if "%product_read%"=="P725A02" goto CHKPRODUCT-DONE)
if "%product%"=="P768A02" (
    if "%product_read%"=="P768S01" goto CHKPRODUCT-DONE)
if "%product%"=="NX729J" (
    if "%product_read%"=="NX729J-UN" goto CHKPRODUCT-DONE)
if "%product%"=="NX769J" (
    if "%product_read%"=="PQ83A01" goto CHKPRODUCT-DONE)
if "%product%"=="NP03J" (
    if "%product_read%"=="PQ83P01" goto CHKPRODUCT-DONE
    if "%product_read%"=="PQ83P02" goto CHKPRODUCT-DONE)
if "%product%"=="NX741J" (
    if "%product_read%"=="PQ85A01" goto CHKPRODUCT-DONE)
if "%product%"=="NP05J" (
    if "%product_read%"=="PQ84P01" goto CHKPRODUCT-DONE)
if "%product%"=="NX779J" (
    if "%product_read%"=="PQ83A06" goto CHKPRODUCT-DONE)
if "%product%"=="NP02J" (
    if "%product_read%"=="K68" goto CHKPRODUCT-DONE)
if "%product%"=="NX733J" (
    if "%product_read%"=="NX733J_NY" goto CHKPRODUCT-DONE
    if "%product_read%"=="NX736J" goto CHKPRODUCT-DONE
    if "%product_read%"=="PQ84A01" goto CHKPRODUCT-DONE)
call log %logger% W 型号不符:实际型号:%product_read%.已选型号:%product%
ECHOC {%c_w%}型号错误. 当前机型%product_read%与工具箱型号%product%不一致. 如果你确定机型无误, 请按任意键继续, 并截图向开发者反馈. 否则请不要继续.{%c_i%}{\n}
pause>nul
ENDLOCAL
goto :eof
:CHKPRODUCT-DONE
call log %logger% I 型号检查通过:实际型号:%product_read%.已选型号:%product%
ENDLOCAL
goto :eof


:EDLREADALL
SETLOCAL
set edlreadall_customize=n
set logger=ztetoolbox.bat-edlreadall
::接收变量
set port=%args2%& set imgpath=%args3%& set fh=%args4%
call log %logger% I 接收变量:port:%port%.imgpath:%imgpath%.fh:%fh%
:EDLREADALL-1
::检查img存放目录和引导文件是否存在
if not exist %imgpath% ECHOC {%c_e%}找不到%imgpath%{%c_i%}{\n}& call log %logger% F 找不到%imgpath%& goto FATAL
if not "%fh%"=="" (if not exist %fh% ECHOC {%c_e%}找不到%fh%{%c_i%}{\n}& call log %logger% F 找不到%fh%& goto FATAL)
::如果端口号为auto或空则自动检查端口
if not "%port%"=="auto" (if not "%port%"=="" goto EDLREADALL-2)
call chkdev qcedl 1>nul
set port=%chkdev__port__qcedl%
:EDLREADALL-2
::发送引导
if not "%fh%"=="" call write qcedlsendfh %port% %fh% auto
::读取设备信息
call info qcedl %port%
if not "%info__qcedl__portstatus%"=="firehose" ECHOC {%c_e%}端口不在firehose模式. 请发送引导并配置端口后再试. {%c_h%}按任意键重试...{%c_i%}{\n}& call log %logger% E 端口不在firehose模式& pause>nul & ECHO.重试... & goto EDLREADALL-2
::创建目录
if not exist %imgpath%\images md %imgpath%\images 1>>%logfile% 2>&1
if not exist %imgpath%\for_ROM_maker md %imgpath%\for_ROM_maker 1>>%logfile% 2>&1
if exist tool\Other\ReadAllFunc_Readme_Chs.txt copy /Y tool\Other\ReadAllFunc_Readme_Chs.txt %imgpath%\for_ROM_maker\本目录说明.txt 1>nul
if exist tool\Other\ReadAllFunc_Readme_Eng.txt copy /Y tool\Other\ReadAllFunc_Readme_Eng.txt %imgpath%\for_ROM_maker\readme.txt 1>nul
if not exist %imgpath%\for_ROM_maker\orig md %imgpath%\for_ROM_maker\orig 1>>%logfile% 2>&1
if not exist %imgpath%\for_ROM_maker\generate md %imgpath%\for_ROM_maker\generate 1>>%logfile% 2>&1
::回读, 解析分区表文件
::    生成partition.xml表头
echo.^<?xml version="1.0" ?^>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.^<configuration^>>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.^<parser_instructions^>>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.WRITE_PROTECT_BOUNDARY_IN_KB=0|find "=" 1>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.SECTOR_SIZE_IN_BYTES = %info__qcedl__secsize%|find "=" 1>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.GROW_LAST_PARTITION_TO_FILL_DISK=true>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.^</parser_instructions^>>>%imgpath%\for_ROM_maker\orig\partition.xml
set xmls=
set num=0
:EDLREADALL-3
::    所有lun解析完成, 继续下一步
if "%num%"=="%info__qcedl__lunnum%" goto EDLREADALL-5
echo.^<?xml version="1.0" ?^>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml& echo.^<data^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
call partable readgpt qcedl %info__qcedl__memtype% %num% gptmain %imgpath%\for_ROM_maker\orig\gpt_main%num%.bin notice %port%
call partable readgpt qcedl %info__qcedl__memtype% %num% gptbackup %imgpath%\for_ROM_maker\orig\gpt_backup%num%.bin notice %port%
call log %logger% I 解析分区表%num%
::ptanalyzer.exe -f %imgpath%\for_ROM_maker\orig\gpt_main%num%.bin -m %info__qcedl__memtype% -t gptmain -o normal_clear -shownonpartitioned y 1>%tmpdir%\output.txt 2>&1 || type %tmpdir%\output.txt>>%logfile% && ECHOC {%c_e%}解析分区表%num%失败{%c_e%}&& call log %logger% F 解析分区表%num%失败&& goto FATAL
::type %tmpdir%\output.txt>>%logfile%
gpttool.exe -p %imgpath%\for_ROM_maker\orig\gpt_main%num%.bin -f print:default:default:sector:10 -o %tmpdir%\output.txt 1>>%logfile% 2>&1 || ECHOC {%c_e%}解析分区表%num%失败{%c_e%}&& call log %logger% F 解析分区表%num%失败&& goto FATAL
::    将目标lun分区信息写入partition.xml
echo.^<physical_partition^>>>%imgpath%\for_ROM_maker\orig\partition.xml
::ptanalyzer.exe -f %imgpath%\for_ROM_maker\orig\gpt_main%num%.bin -m %info__qcedl__memtype% -t gptmain -o xml_partition -shownonpartitioned y | find "partition label=" 1>>%imgpath%\for_ROM_maker\orig\partition.xml
gpttool.exe -p %imgpath%\for_ROM_maker\orig\gpt_main%num%.bin -f print:qcedl_partitionxml -o %tmpdir%\tmp.txt 1>>%logfile% 2>&1 || ECHOC {%c_e%}解析分区表%num%失败{%c_e%}&& call log %logger% F 解析分区表%num%失败&& goto FATAL
type %tmpdir%\tmp.txt>>%imgpath%\for_ROM_maker\orig\partition.xml
echo.^</physical_partition^>>>%imgpath%\for_ROM_maker\orig\partition.xml
::    生成edlreadall-parlist.txt, 请求用户确认要回读的分区
echo.请确认分区表%num%中要回读的分区或区域. Unalloc_xxx是未分区的空间. 删掉[]代表不回读该分区或区域. 关闭并保存文档代表确认...>%tmpdir%\edlreadall-parlist.txt
for /f "tokens=3,6 delims= " %%a in ('type "%tmpdir%\output.txt" ^| find "["') do echo.[%%a]          %%b >>%tmpdir%\edlreadall-parlist.txt
busybox.exe sed -i "s/\[userdata\]/userdata/g;s/\[last_parti\]/last_parti/g;s/\[mindowsesp\]/mindowsesp/g;s/\[mindowswin\]/mindowswin/g;s/\[mindowsdat\]/mindowsdat/g" %tmpdir%\edlreadall-parlist.txt
if "%edlreadall_customize%"=="y" ECHOC {%c_h%}等待确认分区表%num%回读分区...{%c_i%}{\n}& start /wait tool\Win\Notepad3\Notepad3.exe %tmpdir%\edlreadall-parlist.txt & ECHO.继续...
set num2=1
:EDLREADALL-4
set parname=& set parsizesec=
for /f "tokens=3,4,6 delims= " %%a in ('type %tmpdir%\output.txt ^| find "[Item%num2%]"') do set parname=%%a& set parstartsec=%%b& set parsizesec=%%c
::    fastboot线刷脚本, 在当前lun第1个分区前加入此lun的分区表刷入脚本
if "%num2%"=="1" echo.::fastboot flash partition:%num% %%~dp0images\gpt_both%num%.bin ^|^| @echo "Flash gpt_both%num%.bin error" >>%imgpath%\flash_all.bat
::    分区名为空代表已读完目标lun分区. 继续读下一个lun
if "%parname%"=="" (
    if "%info__qcedl__memtype%"=="ufs" (
        echo.^<program filename="gpt_main%num%.bin" label="PrimaryGPT" physical_partition_number="%num%" start_sector="0" num_partition_sectors="6" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
        echo.^<program filename="gpt_backup%num%.bin" label="BackupGPT" physical_partition_number="%num%" start_sector="NUM_DISK_SECTORS-5." num_partition_sectors="5" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
        echo.^</data^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml)
    if not "%info__qcedl__memtype%"=="ufs" (
        echo.^<program filename="gpt_main%num%.bin" label="PrimaryGPT" physical_partition_number="%num%" start_sector="0" num_partition_sectors="34" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
        echo.^<program filename="gpt_backup%num%.bin" label="BackupGPT" physical_partition_number="%num%" start_sector="NUM_DISK_SECTORS-33." num_partition_sectors="33" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
        echo.^</data^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml)
    set xmls=%xmls%/%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
    set /a num+=1& goto EDLREADALL-3)
if "%parsizesec%"=="" ECHOC {%c_e%}分区%parname%有错误{%c_e%}& call log %logger% F 分区%parname%有错误& goto FATAL
::找到目标分区, 写入分区数据
find "[%parname%]" "%tmpdir%\edlreadall-parlist.txt" 1>nul 2>nul || goto EDLREADALL-6
goto EDLREADALL-7
:EDLREADALL-6
echo.^<program filename="" label="%parname%" physical_partition_number="%num%" start_sector="%parstartsec%" num_partition_sectors="%parsizesec%" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
echo.::fastboot flash %parname% %%~dp0images\%parname%.img ^|^| @echo "Flash %parname% error" >>%imgpath%\flash_all.bat
call log %logger% I 跳过9008回读%parname%.lun:%num%.分区编号:%num2%.起始扇区:%parstartsec%.扇区数目:%parsizesec%
goto EDLREADALL-8
:EDLREADALL-7
echo.^<program filename="%parname%.img" label="%parname%" physical_partition_number="%num%" start_sector="%parstartsec%" num_partition_sectors="%parsizesec%" SECTOR_SIZE_IN_BYTES="%info__qcedl__secsize%"/^>>>%imgpath%\for_ROM_maker\orig\rawprogram%num%.xml
echo.fastboot flash %parname% %%~dp0images\%parname%.img ^|^| @echo "Flash %parname% error" >>%imgpath%\flash_all.bat
goto EDLREADALL-8
:EDLREADALL-8
set /a num2+=1& goto EDLREADALL-4
:EDLREADALL-5
echo.^</configuration^>>>%imgpath%\for_ROM_maker\orig\partition.xml
if exist tool\Win\ptool.exe (
    ECHO.开始生成分区表和xml文件...
    call log %logger% I 开始生成分区表和xml文件
    ptool.exe -x %imgpath%\for_ROM_maker\orig\partition.xml -t %imgpath%\for_ROM_maker\generate 1>>%logfile% 2>&1
    call log %logger% I 生成分区表和xml文件完成)
::开始回读
ECHO.开始回读... & call read qcedlxml %port% %info__qcedl__memtype% %imgpath%\images %xmls%
::复制rawprogram.xml
copy /Y %imgpath%\for_ROM_maker\orig\rawprogram*.xml %imgpath%\images 1>>%logfile% 2>&1
call log %logger% I 9008回读全分区完成
ENDLOCAL
goto :eof


:EDLSETBOOTABLESTORAGEDRIVE
SETLOCAL
set logger=ztetoolbox.bat-edlsetbootablestoragedrive
set port=%args2%& set storagetype=%args3%& set fh=%args4%
call log %logger% I 接收变量:port:%port%.storagetype:%storagetype%.fh:%fh%
:EDLSETBOOTABLESTORAGEDRIVE-1
::检查引导文件是否存在
if not "%fh%"=="" (if not exist %fh% ECHOC {%c_e%}找不到%fh%{%c_i%}{\n}& call log %logger% F 找不到%fh%& goto FATAL)
::发送引导
if not "%fh%"=="" call write qcedlsendfh %port% %fh% %storagetype%
::确定存储类型
set storagetype_use=%storagetype%
if "%storagetype%"=="auto" call info qcedl %port%
if "%storagetype%"=="auto" set storagetype_use=%info__qcedl__memtype%
::开始
set value=
if "%storagetype_use%"=="emmc"   set value=0
if "%storagetype_use%"=="spinor" set value=0
if "%storagetype_use%"=="ufs"    ECHO.检查槽位... & call slot qcedl chk
if "%storagetype_use%"=="ufs"    (
    ::注意: 此处需要修改slot.bat
    if "%slot__cur%"=="aonly" set value=1
    if "%slot__cur%"=="a"     set value=1
    if "%slot__cur%"=="b"     set value=2)
if not "%value%"=="" (
    echo.^<?xml version="1.0" ?^>^<data^>^<setbootablestoragedrive value="%value%" /^>^</data^>>%tmpdir%\cmd.xml
    fh_loader.exe --port=\\.\COM%port% --memoryname=%storagetype_use% --search_path=%tmpdir% --sendxml=cmd.xml --mainoutputdir=%tmpdir% --skip_config --noprompt 1>>%logfile% 2>&1 || ECHOC {%c_e%}setbootablestoragedrive %value%失败{%c_i%}{\n}&& call log %logger% E setbootablestoragedrive%value%失败
)
call log %logger% I edlsetbootablestoragedrive%value%完成
ENDLOCAL & set edlsetbootablestoragedrive__value=%value%
goto :eof


:CONFEDITIONPRE
SETLOCAL
set num=2
if exist %tmpdir%\cmd.bat del %tmpdir%\cmd.bat 1>nul
:CONFEDITIONPRE-1
if %num% GTR 31 ECHOC {%c_e%}配置项目过多, 超出可容纳范围{%c_i%}{\n}& goto FATAL
for /f "tokens=%num% delims=[]," %%i in ('find "[edition_str]" "res\%product%\edition.csv"') do set name=%%i
if "%name%"=="done" goto CONFEDITIONPRE-2
for /f "tokens=%num% delims=," %%i in ('find "[%edition_str%]" "res\%product%\edition.csv"') do set value=%%i
echo.set %name%=%value%|find "set" 1>>%tmpdir%\cmd.bat
set /a num+=1
goto CONFEDITIONPRE-1
:CONFEDITIONPRE-2
ENDLOCAL
call %tmpdir%\cmd.bat
goto :eof


:CONFDEVPRE
SETLOCAL
set logger=ztetoolbox.bat-confdevpre
set num=2
:CONFDEVPRE-1
if %num% GTR 31 ECHOC {%c_e%}配置项目过多, 超出可容纳范围{%c_i%}{\n}& goto FATAL
for /f "tokens=%num% delims=[]," %%i in ('find "[product]" "conf\dev.csv"') do set name=%%i
if "%name%"=="done" goto CONFDEVPRE-2
for /f "tokens=%num% delims=," %%i in ('find "[%product%]" "conf\dev.csv"') do set value=%%i
call framework conf dev-%product%.bat %name% %value%
set /a num+=1
goto CONFDEVPRE-1
:CONFDEVPRE-2
ENDLOCAL
call conf\dev-%product%.bat
goto :eof










:FATAL
ECHO. & if exist tool\Win\ECHOC.exe (tool\Win\ECHOC {%c_e%}抱歉, 脚本遇到问题, 无法继续运行. 请查看日志. {%c_h%}按任意键退出...{%c_i%}{\n}& pause>nul & EXIT) else (ECHO.抱歉, 脚本遇到问题, 无法继续运行. 按任意键退出...& pause>nul & EXIT)


