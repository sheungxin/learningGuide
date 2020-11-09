# 场景描述
在String练习中遇到以下问题，注释掉第一行输出true，加上第一行输出false，代码如下：
```Java
SimpleDateFormat simpleDateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"); 

String s3 = new String("1") + new String("1"); 
s3.intern(); 
String s4 = "11"; 
System.out.println(s3 == s4);
```

# 问题分析

intern方法在jdk7及以上的特性：
* 当常量池中不存在"11"这个字符串的引用，将对象s3的引用加入常量池，返回对象s3的引用
* 当常量池中存在"11"这个字符串的引用，返回常量池中的引用

先不看第一行，逐行分析以上代码

* `String s3 = new String("1") + new String("1");`：会生成两个匿名对象和对象s3，同时在字符串常量池放入"1"。
* `s3.intern()`：由于字符串常量池中找不到"11"，把对象s3的引用放入字符串常量池中
* `String s4 = "11"`：由于字符串常量池中已存在"11"，此时s4指向对象s3的引用
* `System.out.println(s3 == s4)`：s3、s4指向同一个引用，因此输出true

**但是加上第一行，输出就变成false了，为什么？**
猜测：SimpleDateFormat创建时向常量池中添加了"11"，因为是和时间相关，改成"10"、"12"都输出false，"13"又变成true，基本可以验证我们的猜想。接下来看看在什么时候向常量池中添加了"11"

# 验证
快速定位方法，执行以下代码，简化debug追踪路径：

```Java
LocaleProviderAdapter adapter = LocaleProviderAdapter.getAdapter(DateFormatSymbolsProvider.class, locale); 
ResourceBundle resource = ((ResourceBundleBasedAdapter)adapter).getLocaleData().getDateFormatData(locale); resource.getStringArray("MonthNames"); 

String s3 = new String("1") + new String("1"); 
s3.intern(); 
String s4 = "11";
System.out.println(s3 == s4);
```

完整debug追踪路径如下：

* SimpleDateFormat初始化时需要调用：DateFormatSymbols.getInstanceRef(locale)

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735661ccc01ef51?w=1194&h=507&f=png&s=44940)

* DateFormatSymbols类中接着调用getProviderInstance(locale)实例化DateFormatSymbols对象

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735663b82292bf3?w=1138&h=292&f=png&s=29633)

* 通过一个Provider生成DateFormatSymbols实例

    ![](https://user-gold-cdn.xitu.io/2020/7/16/17356642b2b80c48?w=1199&h=430&f=png&s=49465)

* provider的实现类DateFormatSymbolsProviderImpl直接调用其构造函数
  
    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735664c6c598574?w=931&h=533&f=png&s=47114)

* 构造函数中进行初始化：initializeData(locale)

    ![](https://user-gold-cdn.xitu.io/2020/7/16/173566679db79538?w=644&h=183&f=png&s=9555)

* initializeData中构建ResourceBundle

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735666ad8faeaef?w=1367&h=800&f=png&s=95105)

* ResourceBundle构建好后，获取months数组，调用：resource.getStringArray("MonthNames")

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735666e1ece8e45?w=1019&h=673&f=png&s=82714)

* ResourceBundle中调用getObject(key)

    ![](https://user-gold-cdn.xitu.io/2020/7/16/173566714358bca7?w=1073&h=144&f=png&s=15118)

* 首次执行obj==null，会调用parent.getObject(key)

    ![](https://user-gold-cdn.xitu.io/2020/7/16/173566746bf9776f?w=1143&h=680&f=png&s=54021)

* handleGetObject是一个抽象方法，实际调用的是子类ParallelListResourceBundle中的实现方法

    ![](https://user-gold-cdn.xitu.io/2020/7/16/17356677ad6c6080?w=768&h=339&f=png&s=24600)

* 在loadLookupTablesIfNecessary中会调用this.getContents()

    ![](https://user-gold-cdn.xitu.io/2020/7/16/17356679f3bab05d?w=953&h=604&f=png&s=43518)

* var2是一个二维数组，看下标4的位置1~12的字符串

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735667c8cf051a2?w=914&h=663&f=png&s=66360)

* 接下来我们看下this.getContents()，这也是个抽象方法，定位到其实现类FormatData

    ![](https://user-gold-cdn.xitu.io/2020/7/16/1735667e59fc8187?w=1742&h=493&f=png&s=59584)

* 下面是getContents()的返回内容，大量的字符串

```JSON
{
	{
		"MonthNames",
		new String\[\] {
			"January",
			"February",
			"March",
			"April",
			"May",
			"June",
			"July",
			"August",
			"September",
			"October",
			"November",
			"December",
			""
		}
	}, {
		"MonthAbbreviations",
		new String\[\] {
			"Jan",
			"Feb",
			"Mar",
			"Apr",
			"May",
			"Jun",
			"Jul",
			"Aug",
			"Sep",
			"Oct",
			"Nov",
			"Dec",
			""
		}
	}, {
		"MonthNarrows",
		new String\[\] {
			"1",
			"2",
			"3",
			"4",
			"5",
			"6",
			"7",
			"8",
			"9",
			"10",
			"11",
			"12",
			""
		}
	}, {
		"DayNames",
		new String\[\] {
			"Sunday",
			"Monday",
			"Tuesday",
			"Wednesday",
			"Thursday",
			"Friday",
			"Saturday"
		}
	}, {
		"DayAbbreviations",
		new String\[\] {
			"Sun",
			"Mon",
			"Tue",
			"Wed",
			"Thu",
			"Fri",
			"Sat"
		}
	}, {
		"DayNarrows",
		new String\[\] {
			"S",
			"M",
			"T",
			"W",
			"T",
			"F",
			"S"
		}
	}, {
		"AmPmMarkers",
		new String\[\] {
			"AM",
			"PM"
		}
	}, {
		"narrow.AmPmMarkers",
		new String\[\] {
			"a",
			"p"
		}
	}, {
		"Eras",
		var1
	}, {
		"short.Eras",
		var1
	}, {
		"narrow.Eras",
		new String\[\] {
			"B",
			"A"
		}
	}, {
		"buddhist.Eras",
		var2
	}, {
		"buddhist.short.Eras",
		var2
	}, {
		"buddhist.narrow.Eras",
		var2
	}, {
		"japanese.Eras",
		var4
	}, {
		"japanese.short.Eras",
		var3
	}, {
		"japanese.narrow.Eras",
		var3
	}, {
		"japanese.FirstYear",
		new String\[0\]
	}, {
		"NumberPatterns",
		new String\[\] {
			"#,##0.###;-#,##0.###",
			"¤ #,##0.00;-¤ #,##0.00",
			"#,##0%"
		}
	}, {
		"DefaultNumberingSystem",
		""
	}, {
		"NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"0",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"�"
		}
	}, {
		"arab.NumberElements",
		new String\[\] {
			"٫",
			"٬",
			"؛",
			"٪",
			"٠",
			"#",
			"-",
			"اس",
			"؉",
			"∞",
			"NaN"
		}
	}, {
		"arabext.NumberElements",
		new String\[\] {
			"٫",
			"٬",
			"؛",
			"٪",
			"۰",
			"#",
			"-",
			"×۱۰^",
			"؉",
			"∞",
			"NaN"
		}
	}, {
		"bali.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᭐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"beng.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"০",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"cham.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꩐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"deva.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"०",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"fullwide.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"０",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"gujr.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"૦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"guru.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"੦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"java.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꧐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"kali.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꤀",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"khmr.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"០",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"knda.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"೦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"laoo.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"໐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"lana.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᪀",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"lanatham.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᪐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"latn.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"0",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"�"
		}
	}, {
		"lepc.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᱀",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"limb.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᥆",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"mlym.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"൦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"mong.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᠐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"mtei.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꯰",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"mymr.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"၀",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"mymrshan.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"႐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"nkoo.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"߀",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"olck.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᱐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"orya.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"୦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"saur.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꣐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"sund.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᮰",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"talu.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"᧐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"tamldec.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"௦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"telu.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"౦",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"thai.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"๐",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"�"
		}
	}, {
		"tibt.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"༠",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"vaii.NumberElements",
		new String\[\] {
			".",
			",",
			";",
			"%",
			"꘠",
			"#",
			"-",
			"E",
			"‰",
			"∞",
			"NaN"
		}
	}, {
		"TimePatterns",
		new String\[\] {
			"h:mm:ss a z",
			"h:mm:ss a z",
			"h:mm:ss a",
			"h:mm a"
		}
	}, {
		"DatePatterns",
		new String\[\] {
			"EEEE, MMMM d, yyyy",
			"MMMM d, yyyy",
			"MMM d, yyyy",
			"M/d/yy"
		}
	}, {
		"DateTimePatterns",
		new String\[\] {
			"{1} {0}"
		}
	}, {
		"buddhist.TimePatterns",
		new String\[\] {
			"H:mm:ss z",
			"H:mm:ss z",
			"H:mm:ss",
			"H:mm"
		}
	}, {
		"buddhist.DatePatterns",
		new String\[\] {
			"EEEE d MMMM G yyyy",
			"d MMMM yyyy",
			"d MMM yyyy",
			"d/M/yyyy"
		}
	}, {
		"buddhist.DateTimePatterns",
		new String\[\] {
			"{1}, {0}"
		}
	}, {
		"japanese.TimePatterns",
		new String\[\] {
			"h:mm:ss a z",
			"h:mm:ss a z",
			"h:mm:ss a",
			"h:mm a"
		}
	}, {
		"japanese.DatePatterns",
		new String\[\] {
			"GGGG yyyy MMMM d (EEEE)",
			"GGGG yyyy MMMM d",
			"GGGG yyyy MMM d",
			"Gy.MM.dd"
		}
	}, {
		"japanese.DateTimePatterns",
		new String\[\] {
			"{1} {0}"
		}
	}, {
		"DateTimePatternChars",
		"GyMdkHmsSEDFwWahKzZ"
	}, {
		"calendarname.islamic-umalqura",
		"Islamic Umm al-Qura Calendar"
	}
}
```
# 使用方式
   由上可知，创建一个SimpleDateFormat对象会加载挺多内容。那么，使用时能否只创建一个实例，使用单例模式呢？
   答案是否，因为SimpleDateFormat 是非线程安全的，正确的打开方式如下：
* **使用ThreadLocal**
```
public static ThreadLocal<DateFormat> safeSdf = new ThreadLocal<DateFormat>() {
    @Override 
    protected SimpleDateFormat initialValue() {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
    }
}
```
* **DateTimeFormatter**
```
// 解析日期
String dateStr= "2020-07-16";
String dateStr = "2020-07-16";
DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd");
LocalDate date = LocalDate.parse(dateStr, formatter);
System.out.println(date);

// 日期转换为字符串
LocalDateTime now = LocalDateTime.now();
DateTimeFormatter format = DateTimeFormatter.ofPattern("yyyy-MM-dd hh:mm:ss");
String nowStr = now.format(format);
System.out.println(nowStr);
```

​    