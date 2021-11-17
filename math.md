$\log_am+\log_an=\log_amn$

$\log_am-\log_an=\log_a\frac{m}{n}$

$\log_a^mb^n=\frac{n}{m}\log_ab$

$log_ab=\frac{\log_cb}{\log_ca}$



$(a \pm b \pm c)^2=a^2+b^2+c^2 \pm 2ab \pm 2ac+2bc$

$a^2+b^2+c^2 \pm ab \pm ac \pm bc=\frac{1}{2}[(a \pm b)^2+(a \pm c)^2+(b \pm c)^2]$

$(a \pm b)^3=(a \pm b)(a^2 \pm 2ab+b^2)=a^3 \pm 3a^2b+3ab^2+b^3$

$a^3 \pm b^3=(a \pm b)(a^2 \mp ab+b^2)$

 $ab=\frac{(a+b)^2-(a-b)^2}{4}$

$2(ab+ac+bc)=(a+b+c)^2-(a^2+b^2+c^2)$

$\frac{1}{a}+\frac{1}{b}+\frac{1}{c}=0 => ab+ac+bc=0 => a^2+b^2+c^2=(a+b+c)^2$

$f(x)=(ax-b)g(x)+r(x),当f(x)能被(ax-b)整除，f(\frac{b}{a})=0$



一元二次方程的三种形式：

- $y=ax^2+bx+c$，y轴截距：y=c，当c=0时，函数图像过坐标原点

- $y=a(x+\frac{b}{2a})^2+\frac{4ac-b^2}{4a}$，其中$(-\frac{b}{2a},\frac{4ac-b^2}{4a})$为顶点坐标，a>0(a<0)时，有最小(大)值$\frac{4ac-b^2}{4a}$，无最大(小)值

- $y=a(x-x_1)(x-x_2)$，其中$x_1$、$x_2$表示一元二次函数与x轴的两个交点，或方程的两个根

一元二次方程根依$\Delta=b^2-4ac$分为以下三种情况：

- $\Delta>0$时，有两个不等实根，根的表达式$x_1,x_2=\frac{-b\pm \sqrt{\Delta}}{2a}$
- $\Delta=0$时，有两个相等实根，根的表达式$x_1,x_2=-\frac{b}{2a}$
- $\Delta<0$时，无实根



韦达定理
$$
ax^2+bx+c(a\ne0,x_1,x_2是方程两个根)\Rightarrow 
\begin{cases}
x_1+x_2=-\frac{b}{a} \\
x_1*x_2=\frac{c}{a}
\end{cases}\\ \Rightarrow
\begin{cases}
\frac{1}{x_1}+\frac{1}{x_2}=\frac{x_1+x_2}{x_1x_2} \\
\frac{1}{{x_1}^2}+\frac{1}{{x_2}^2}=\frac{(x_1+x_2)^2-2x_1x_2}{(x_1x_2)^2} \\
|x_1-x_2|=\sqrt{(x_1-x_2)^2}=\sqrt{(x_1+x_2)^2-4x_1x_2}\\
{x_1}^2+{x_2}^2=(x_1+x_2)^2-2x_1x_2\\
{x_1}^2-{x_2}^2=(x_1+x_2)(x_1-x_2)\\
{x_3}^3+{x_3}^3=(x_1+x_2)({x_1}^2-x_1x_2+{x_2}^2)=(x_1+x_2)[(x_1+x_2)^2-3x_1x_2]
\end{cases}
$$


二次六项式$ax^2+bxy+cy^2+dx+ey+f$，可以用双十字相除法进行因式分解，分解过程如下：

- 用十字相乘法分解$ax^2+bxy+cy^2$
- 把常数项f分解成两个因式填在第三列上，要求第二、第三列构成的十字交叉之积的和等于原式的$ey$，要求第一、第三列构成的十字交叉之积的和等于原式的$dx$



方程组三种解的情况：
$$
\begin{cases}
a_1x+b_1y=c_1 \\
a_2x+b_2y=c_2
\end{cases}
$$

- 如果$\frac{a1}{a2}\ne\frac{b1}{b2}$，则方程组有唯一解
- 如果$\frac{a1}{a2}=\frac{b1}{b2}=\frac{c1}{c2}$，则方程组有无穷多解
- 如果$\frac{a1}{a2}=\frac{b1}{b2}\ne\frac{c1}{c2}$，则方程组无解



算术平均数和几何平均数基本定理：

$\frac{x_1+x_2+...+x_n}{n} \ge \sqrt[n]{x_1x_2...x_n}(x_1>0,i=1,...,n)$

- 当乘集为定值时，和有最小值：$\ge n\sqrt[n]{积}$
- 当和为定值时，乘集有最大值：积$\le(\frac{和}{n})^n$
- 当$n=2$时，$a+b\ge2\sqrt{ab}(a,b>0)\Rightarrow a+\frac{1}{a}\ge 2(a\gt 0)$

验证给定函数是否满足最值三个条件：一正二定三相等

- 各项均为正
- 乘积（或和）为定值
- 等号能否取到



绝对值函数：

- $y=|ax+b|$：$x$轴下方的图像翻到$x$轴上方
- $u=|ax^2+bx+c|$：$x$轴下方的图像翻到$x$轴上方
- $|ax+by|=c$：表示两条平行的直线$ax+by=\pm c$，且两者关于原点对称
- $|ax|+|by|=c$：当$a=b$时，表示正方形，反之表示菱形
- $|xy|+ab=a|x|+b|y|$：表示由$x=\pm b,y=\pm a$围成的正方形或矩形，面积为$4ab$
  $|xy|+ab=a|x|+b|y| \Rightarrow |x||y|-a|x|-b|y|+ab=0 \Rightarrow |x|(|y|-a)-b(|y|-a)=0 \Rightarrow (|y|-a)(|x|-b)=0\Rightarrow |x|=b或|y|=a$

 绝对值不等式解法：

- 分段讨论法

  $|f(x)|=\begin{cases} f(x) &f(x)\ge 0\\ -f(x) &f(x)<0 \end{cases}$

- 平方法

  $(|f(x)|)^2=[f(x)]^2$

- 公式法

  $|f(x)|<a(a>0)\Leftrightarrow -a<f(x)<a$

  $|f(x)|>a(a>0)\Leftrightarrow f(x)<-a 或 f(x)>a$

  $|f(x)|<g(x)\Leftrightarrow -g(x)<f(x)<g(x)(g(x)>0)$

  $|f(x)|>g(x)\Leftrightarrow f(x)>g(x)或f(x)<-g(x)(g(x)>0)$

- 图像法



分式不等式，注意先移项，使右边为0

- $\frac{x-a}{x-b}\ge 0(a<b) \Rightarrow x\le a或x>b$
- $\frac{x-a}{x-b}\le 0(a<b) \Rightarrow a\le x<b$
- $\frac{f(x)}{g(x)}>0\Leftrightarrow f(x)g(x)>0$
- $\frac{f(x)}{g(x)}<0\Leftrightarrow f(x)g(x)<0$
- $\frac{f(x)}{g(x)}\ge0\Leftrightarrow \begin{cases}f(x)g(x)\ge0\\ g(x)\ne0\end{cases}$
- $\frac{f(x)}{g(x)}\le0\Leftrightarrow \begin{cases}f(x)g(x)\le0\\ g(x)\ne0\end{cases}$

高次不等式-穿线法

- 分解因式，化成若干个因式乘积

- 作等价变形，便于判断因式的符号，例如：$x^2+1,x^2+x+1,x^2-3x+5等，无论$$x$取何值，式子的代数值均大于0

- 由小到大，从左到右标出与不等式对应的方程的根

- 从右上角起，穿针引线

- 重根的处理，依“奇穿偶不穿”原则

- 画出解集的示意区域，例如：$f(x)=(x-x_1)(x-x_2)...(x-x_n)$

  先在数轴上标注出每个因式的零点，然后从右上方穿一条线，遇到零点就穿过一次，图像在数轴上方代表大于零，在数轴下方代表小于零，需要注意的是，对偶数次方的因式，该零点不穿透，另外在使用穿线法的时候，$x$的系数都要转化为正数来分析

无理式不等式，一般是通过平方转化为有理式不等式进行求解。在求解时，注意根号要有意义

遇到指数或对数不等式，给出单调性进行分析，或者换元转化为一般不等式求解，需要注意对数的定义域

柯西不等式

- $(a^2+b^2)(c^2+d^2)\ge(ac+bd)^2\Rightarrow(ad-bc)^2\ge0$