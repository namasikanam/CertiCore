# CertiCore

CertiCore 是清华大学 2020 年操作系统课的一个挑战性实验项目，初衷是尝试对多年用于本课程教学的操作系统[uCore](https://github.com/chyyuu/ucore_os_lab)作形式化验证。遗憾的是，对于参与本项目的二位本科生而言，uCore 是一个过于庞大的宏内核，最终我们只完成了 uCore 中的一个小小的部件——**页面分配器**的部分验证工作。

关于本项目的更多细节，请参阅代码，或我们的[课程最终报告](reports/最终报告.pdf)和[课程最终文档](reports/最终文档.pdf)。

## 安装

为了编译本项目，我们需要

* RISC-V gcc toolchain

如果你在使用 Linux (Ubuntu) ，你可以通过以下指令安装

```bash
$ apt-get install gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
```

### 运行

为了运行本项目，我们需要

* QEMU >= 4.1.0

如果你在使用 Linux (Ubuntu) ，需要到 QEMU 官方网站下载源码并自行编译，因为 Ubuntu 默认的源的 QEMU 的版本过低无法使用。参考命令如下：

```bash
$ wget https://download.qemu.org/qemu-4.1.1.tar.xz
$ tar xvJf qemu-4.1.1.tar.xz
$ cd qemu-4.1.1
$ ./configure --target-list=riscv32-softmmu,riscv64-softmmu
$ make -j
$ export PATH=$PWD/riscv32-softmmu:$PWD/riscv64-softmmu:$PATH
```

可查看[更详细的安装和使用命令](https://github.com/riscv/riscv-qemu/wiki)。同时，我们在每次开机之后要使用此命令来允许模拟器过量使用内存（不是必须的），否则无法正常使用 QEMU：

```bash
$ sudo sysctl vm.overcommit_memory=1
```

安装完成后，即可通过以下指令在模拟器中运行内核
```bash
$ make clean
$ make qemu
```

如果一切正常，你会看到形如下述的输出
```bash
(THU.CST) os is loading...
```
最后，内核会稳定的以一定时间间隔输出
```bash
100 ticks
```
这时，你可以通过快捷键 `Ctrl-A X` 终止 QEMU 的运行。

### 验证

为了验证本项目，我们需要

* Racket >= 7.4

另外，我们需要改进版的 [Serval](https://github.com/linusboyle/Serval)，请将它置于或链接于本项目的根目录下。

安装完成后，可通过如下指令运行验证过程
```bash
$ make clean
$ make verify
```
大约会需要几分钟的时间。