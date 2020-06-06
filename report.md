# Certicore 实验报告

Certicore被设计为是教学OS ucore的形式化验证版本。经过半学期的开发，最终实际实现了ucore中中断以及物理页面分配器的验证。

## 概论

### 形式化验证

使用形式化验证的技术，对OS进行验证已有很长的一段历史。目前主要有三种验证的技术：

1.交互式定理证明。这种方法使用定理证明器(Proof Assistant)如Coq辅助验证，本质上是手动证明，利用证明器的特性可以实现一部分自动化。这种方法要求在形式系统内进行演绎，难度很高。典型的系统包括seL4和CertiKOS。
 
2.使用程序标注辅助证明。通过在程序中显式地插入约束、不变量等，利用证明器自动将其转化为约束求解问题进行求解。这种方式的自动化程度更高，但是手动标注依旧很困难。典型的系统如Komodo。
 
3.完全自动化的求解。这种方式期望验证者集中在编写实现接口、规范上，证明器将通过符号执行过程，自动生成约束，问题最终将被转化为可满足性的判定问题。这种方式简单，但是对实现有一些限制，如要求方法必须是有限的。典型的系统是HyperKernel。

Xi Wang等人按照符号执行的思想，开发了Serval框架。此框架实现了状态机精化，符号执行优化等过程，大大简化了系统验证的开销。我们在此框架的基础上，完成对ucore的验证。

### 工具：Rosette与Serval

Rosette是基于Racket的符号执行引擎。其主要优点是可以在同一个语言框架内完成实现和规范的符号执行。其能力也许不及专用符号执行引擎强大，但是是一种通用符号执行工具。

Serval基于Rosette语言实现，Rosette本身已经提供了一部分符号执行特性。虽然一阶谓词逻辑的可满足性是不可判定的，但是Rosette实现的是其中可判定的子集。因此，编写程序规范时，需要一部分技巧来规避表达力不足的问题。

Serval在此基础上提供了更高级的特性。使用Serval验证系统的基本思路是：

1.使用Rosette编写一个automated verifier, 将系统的实现代码（如汇编，LLVM IR等）转换为符号执行

2.使用Rosette编写程序规范

Serval会使用Rosette生成SMT约束，并在此过程中自动进行优化。验证者无需关心验证的过程，只需专注在程序接口和规范的编写。

### 抽象、精化

Serval提供了准确的状态机精化支持。在Serval中，规范由四部份组成，都在Rosette中编写：

1.程序的抽象状态s
2.程序的预期运行行fspec
3.一个将程序具体状态映射到抽象状态的abstract function（AF）
4.程序执行前后的不变量RI

精化通过后，我们就可以用抽象状态编写更多的规范。

比如，欲验证状态的转移与某变量无关(noninterference)，为此，我们只需考虑抽象状态的转移。Serval提供了大量的内置方法刻画常见的程序属性，在这个例子中，可以使用其提供的step consistency属性。我们只需要在状态空间上定义一个二元谓词∼描述状态间的等价关系。在我们的验证过程中，就利用了这一方法。

## 验证

### Timer

以下是一个示例中断处理例程：

```c
case IRQ_S_TIMER:
clock_set_next_event();
if (++ticks % TICK_NUM == 0) {
print_ticks();
}
break;
```

我们验证了其正确性。在抽象状态中，只有一个ticks变量：

```racket
(struct state (tick)
#:transparent
#:mutable)
(define (intrp-timer st)
(set-state-tick! st
(bvadd (state-tick st) (bv 1 64))))
```

### 页面分配器

我们的验证是细粒度的，在算法层面验证了ucore的页面分配是first fit的。因此状态空间更大，求解难度也更高。

分配算法的核心代码：

```c
for (size_t p = 0; p < NPAGE; p ++)
if (PageReserved(p) || PageAllocated(p)) {
first_usable = p + 1;
}
else {
if (p - first_usable + 1 == n) {
page = first_usable;
break; // found! 'page' is allocated!
}
}
```

我们用函数类型表示pages的元数据，并记录下剩余的空闲页面。我们用lambda表达式g = λx.ite(x = i)v(fx)表示pages数据的更新。

rosette编写的规范：

```racket
(define (find-free-pages s num)
(define (find-free-accumulate lst acc ans)
(cond
[(bveq num acc) ans]
[(null? lst) #f]
[(page-available? s (car lst))
(find-free-accumulate
(cdr lst) (bvadd1 acc)
(if (bveq acc (bv 0 64)) (car lst) ans))]
[else (find-free-accumulate (cdr lst) (bv 0 64)
(define indexl (map bv64 (range constant:NPAGE)))
(find-free-accumulate indexl (bv 0 64) (bv 0 64)))
```

因为是递归函数，实际验证比较缓慢。

除了分配算法，我们还验证了其他接口，包括：

- 内存初始化
- 页面释放
- 查询剩余页面数

值得一提的是，因为分配算法的复杂性，增加pages的大小，会成指数性地增加开销。我们最终是在5页的情况下完成的验证（只在验证时限定为5，实际运行时不是）。


### 和其他项目相比

Serval的示例中有对Certikos和Komodo等OS的验证。这些OS都是微内核，接口非常简单，不涉及复杂的操作。

特别的，页面分配在这些项目中都是用户态考虑的。我们直接在ucore宏内核中验证fisrt-fit分配算法的正确性，的确比较困难（开发上，以及开销上）

符号执行的特点决定了用这种方法，所能验证的接口必然是受限的。有时我们能用重写的方法规避，有时则完全受限于符号执行的表达力。

因此，我们认为符号执行的方法只适合于简单的微内核。即使是ucore这样的教学OS，使用这种方法验证都是极其困难的。

## 日志 

###  第十五周 

完成了下述第二条 safety property 的验证。

###  第十四周 

通过使用 statically bounded loop 并让 clang 在编译阶段 unroll，default_free_pages 得以验证。

验证了 pmm_manager 中剩余的其他函数，主要是 default_init_memmap。

但随着页数的增长，验证所需的时间也会爆炸性的增长，目前我们只验证了5页。

按向老师的建议，增加了打印详细的反例的功能。

尝试在精化后的抽象状态机上验证两条 safety property：

-  在初始化一段页面时，这一段之外的页面的状态不会被影响。
-  在释放一段页面时，这一段之外的页面的状态不会被影响。

注：Racket本身已经是一门动态语言，Rosette为了验证需要，会将内部的exception理解为assert，导致调试极为困难，调试手段极为有限。

###  第十三周 

重写了 pmm_manager 的物理内存管理部分，使其充分简化，以便于验证。

对 pmm_manager 作 refine，其核心函数时 default_alloc_pages 和 default_free_pages，目前完成了 default_alloc_pages，default_free_pages 会 timeout。

最初怀疑是 performance 的问题。因为 default_alloc_pages 最初也会 timeout，但将抽象函数的实现更改地更适于验证之后，便可以通过验证了，虽然目前我们处理的页数只有 5。符号执行的过程本身就极为缓慢，我们发现实现上微小的改动可能会对运行的效率和结果造成很大的影响，于是便尝试通过修改C和Rosette的函数实现，试图寻找一个易于符号执行、可以通过验证的版本。但大量的尝试并未起到效果，之后再次阅读了论文（[1](https://unsat.cs.washington.edu/papers/nelson-serval.pdf)，[2](https://homes.cs.washington.edu/~emina/pubs/rosette.onward13.pdf)，[3](https://homes.cs.washington.edu/~emina/pubs/rosette.pldi14.pdf)）对于 bounded loop 的原理的解释之后，发现我们之前对于 bounded loop 的理解是有误的，事实上 Rosette 对于 bounded loop 的解决方案就是静态将其展开尽可能多的次数。而我们的实现是“dynamically bounded”，是 Rosette 无法解决的 case。

###  第十二周 

大致了解了 CertiKOS 和 Komodo 的实现代码和验证过程，惊讶地发现它们都是非常“小”的 OS，比 ucore 都要小很多。Komodo 的主体部分是一个三级页表+enclave，CertiKOS 的主体部分是在做进程管理和处理系统调用，页表是在用户态实现的，并没有对其作验证。

另外，发现riscv-ucore的lab2中其实只有一个非常简单的页表，lab2的主要部分其实是物理内存管理（pmm_manager），打算来对这部分建模并验证。

移植了 riscv-ucore lab2，由于 Serval 不支持原子指令，简便起见我们选择了将其裁剪掉。
 
添加了 LLVM IR 的编译链，lab2 的部分应当可以完全在 LLVM IR 上处理。

尝试修改 pmm_manager 的已有实现，不再记录 priority，而是单纯地在 page table 上做物理内存页面分配，以让验证过程更加简化。

###  第十一周 

完成了 lab1 中 timer 的验证，之前一直失败的原因是 Serval 不支持 print。

在尝试对 lab2 的页表做验证，尝试学习 CertiKOS 和 Komodo 是如何验证页表的，CertiKOS 的做法非常独特，感觉很难借鉴；Komodo 用的似乎是一个比较正常的页表，但还没有看懂它是怎么做的。

###  第十周 
更改Serval，为其RISCV验证模块加入了对S态软件的支持。Fork版本在[这里](https://github.com/linusboyle/serval)。

修改RISCV版本的ucore，使得其适合进行验证。

对lab1版本的ucore尝试进行了验证。

###  第九周 
阅读[toy monitor](https://github.com/uw-unsat/serval-tutorial-sosp19)的源代码，并对前两周 Rosette 和 Toy Monitor 的学习做了分享。

将 Toy Monitor 的 OS 替换为[lab1-minimal](https://github.com/ring00/bbl-ucore/tree/priv-1.10/lab1-minimal)，可以通过验证，但在QEMU上模拟时遇到了错误。

###  第七、八周 
参照[rosette guide](https://docs.racket-lang.org/rosette-guide/index.html)进行了学习，掌握了Rosette语言基本的原理和使用方法。

按照Serval提供的[教程](https://github.com/uw-unsat/serval-tutorial-sosp19)，确定了使用Serval框架验证一个小型操作系统的步骤和方法。

尝试将教程中的 Toy Security Monitor 从 RISCV 迁移到 x32，但遇到了一些困难。

###  第六周 
阅读Serval论文，复现Serval实验，经过讨论后确定了具体选题。

###  第五周 
在戴臻洋学长的建议下，调研了[Xi Wang](https://homes.cs.washington.edu/~xi/)近期的工作，初步调研之后认为可以在''Scaling symbolic valuation for automated verification of systems code with Serval''的基础上展开进一步的工作。论文中声称其框架（[Serval](https://unsat.cs.washington.edu/projects/serval/)）只用了1244行Rosette，写一个LLVM verifier只用了789行Rosette，"This shows that verifiers built using Serval are simple to write, understand, and optimize"。看来属于相当轻量级的验证，工作量应该是比较适合课程设计。

目前来看，我们或许可以做的工作有：

 * 复现：Serval framework, RISC-V verifier, x86-32 verifier, LLVM verifier, BPF verifier, verify CertiKOS, verify Komodo
 * 新的verifier：x86-64 verifier, JVM verifier, [TVM](https://tvm.apache.org/) verifier, ...
 * 新的Verification: ucore, rcore, [CompCert](http://compcert.inria.fr/), [Kami](http://adam.chlipala.net/papers/KamiICFP17/), ...

更进一步的细化方案还有待更进一步的了解。
