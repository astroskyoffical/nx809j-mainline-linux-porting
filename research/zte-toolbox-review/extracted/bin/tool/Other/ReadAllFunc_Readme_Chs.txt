目录说明：

本目录由工具箱回读全分区功能生成，用于制作通用9008线刷救砖包。
如果你需要刷机，请无视本目录中的文件。它们并非用于刷机，也不属于线刷包。images目录内的xml文件用于9008刷机。

orig目录内存放的是设备原始gpt和xml文件，以及根据原始gpt生成的partition.xml文件。
generate目录内存放的是ptool.exe根据partition.xml文件生成的标准gpt和xml文件。

如何做包：

首先建议回读的设备系统为纯官方未经修改，且可以正常开机。因为未解锁BL的设备刷入修改过的系统无法开机。
对于ab分区设备，必须保证设备回读时处于a槽位且可以正常开机。因为大多数9008工具不支持切换到b槽位，刷入在b槽位回读的系统无法开机。
回读完成后，对于ab分区设备，进入images目录，删除所有 *_b.img 文件。重命名去掉所有 *_a.img 文件名中的 _a 。
检查generate目录内是否有文件。如果没有则需要手动使用 ptool.exe -x partition.xml 命令尝试生成，并排查问题。一般是由于某个末位分区（如userdata）大小出现小数，对于末位分区大小出现小数的情况，可以直接将小数去掉重新生成，因为末位分区的大小是自动匹配的，partition.xml里的大小没有任何影响。
将generate目录内的 rawprogram?.xml ， patch?.xml ， gpt_main?.bin ， gpt_backup?.bin ， gpt_both?.bin 覆盖到images目录内。
编辑所有images目录内的 rawprogram?.xml 文件，将文件内的所有 _a.img 和 _b.img 字段全部批量替换为 .img ，也就是让ab槽位都刷同一套镜像文件。
编辑所有images目录内的 rawprogram?.xml 文件，将无需刷入的分区（比如基带，串号分区等）所在行的 filename="xxx" 留空，也就是修改为 filename="" 。这样在刷入时将跳过该分区。建议与官方线刷包的xml对比以确定应该去除哪些分区。
如果需要支持Fastboot线刷，请修改 flash_all.bat ，同样将文件内的所有 _a.img 和 _b.img 字段全部批量替换为 .img ，并删除或注释掉无需刷入的分区所在行。
如果不需要支持Fastboot线刷，请删除 flash_all.bat 。
打包发布。

by 酷安@某贼 2025.6.29

