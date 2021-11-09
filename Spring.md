# 模块组成

![Spring 框架图示](https://sheungxin.github.io/notpic/spring_framework.gif)

- **核心容器** ：核心容器提供 Spring 框架的基本功能。核心容器的主要组件是 `BeanFactory`，它是工厂模式的实现。 `BeanFactory` 使用 *控制反转* （IOC） 模式将应用程序的配置和依赖性规范与实际的应用程序代码分开
- **Spring 上下文** ：Spring 上下文是一个配置文件，向 Spring 框架提供上下文信息。Spring 上下文包括企业服务，例如 JNDI、EJB、电子邮件、国际化、校验和调度功能
- **Spring AOP** ：通过配置管理特性，Spring AOP 模块直接将面向方面的编程功能集成到了 Spring 框架中。所以，可以很容易地使 Spring 框架管理的任何对象支持 AOP。Spring AOP 模块为基于 Spring 的应用程序中的对象提供了事务管理服务。通过使用 Spring AOP，不用依赖 EJB 组件，就可以将声明性事务管理集成到应用程序中
- **Spring DAO** ：JDBC DAO 抽象层提供了有意义的异常层次结构，可用该结构来管理异常处理和不同数据库供应商抛出的错误消息。异常层次结构简化了错误处理，并且极大地降低了需要编写的异常代码数量（例如打开和关闭连接）。Spring DAO 的面向 JDBC 的异常遵从通用的 DAO 异常层次结构
- **Spring ORM** ：Spring 框架插入了若干个 ORM 框架，从而提供了 ORM 的对象关系工具，其中包括 JDO、Hibernate 和 iBatis SQL Map。所有这些都遵从 Spring 的通用事务和 DAO 异常层次结构
- **Spring Web 模块** ：Web 上下文模块建立在应用程序上下文模块之上，为基于 Web 的应用程序提供了上下文。所以，Spring 框架支持与 Jakarta Struts 的集成。Web 模块还简化了处理多部分请求以及将请求参数绑定到域对象的工作
- **Spring MVC 框架** ：MVC 框架是一个全功能的构建 Web 应用程序的 MVC 实现。通过策略接口，MVC 框架变成为高度可配置的，MVC 容纳了大量视图技术，其中包括 JSP、Velocity、Tiles、iText 和 POI

# Spring容器高层视图

![img](https://sheungxin.github.io/notpic/7240015-4669f4f39a4bd7ea)

# BeanFactory 和 ApplicationContext

|                  BeanFactory                   |               ApplicationContext               |
| :--------------------------------------------: | :--------------------------------------------: |
| ![2](https://sheungxin.github.io/notpic/2.png) | ![1](https://sheungxin.github.io/notpic/1.png) |



- BeanFactory 接口位于类结构树的顶端 ，它最主要的方法就是 getBean(String beanName)，该方法从容器中返回特定名称的 Bean，BeanFactory 的功能通过其他的接口得到不断扩展
- ApplicationContext 由 BeanFactory 派生而来，提供了更多面向实际应用的功能

> 参考：
>
> - https://www.jianshu.com/p/9fe5a3c25ab6
> - https://javadoop.com/post/spring-ioc

# Spring Bean 生命周期

![img](https://sheungxin.github.io/notpic/519126-20200215215829265-723152995.png)

> AspectJAwareAdvisorAutoProxyCreator生效的地方，主要是在初始化之后。它实现了postProcessAfterInitialization方法，这个方法，其return的结果，就会取代原有的bean，来存放到ioc容器中

![img](https://sheungxin.github.io/notpic/Xnip2019-07-03_13-45-04.jpg)

***注意：如果指定 Bean 的作用范围为 scope=“prototype”，将初始化后Bean 返回给调用者，调用者负责 Bean 后续生命的管理， Spring 不再管理这个 Bean 的生命周期（即Ready for Use后的@PreDestroy、DisposableBean.destroy()、destroy-method不生效）***

> 参考：https://blog.csdn.net/nuomizhende45/article/details/81158383

## Constructor

对象的创建当然是要调用其构造器，所以 Constructor 毋庸置疑是创建 Spring Bean 的第一步

## Setter Methods

通过 Setter 方法完成依赖注入，SDI （Setter Dependency Injection）

依赖注入可能存在的问题，如下：

- NullPointerException

```java
@Component
public class InvalidInitExampleBean {

    @Autowired
    private Environment env;

    /**
    * 依赖注入在构造器之后，构造器中调用了未进行注入的对象
    */
    public InvalidInitExampleBean() {
        env.getActiveProfiles();
    }

}
```

​	Environment 实例应该在安全注入之后再调用，解决方案如下：

```java
@Component
public class InvalidInitExampleBean {

    @Autowired
    private Environment env;
    
    @PostConstruct
    public void init(){
        env.getActiveProfiles();
    }

}
```

- 循环注入问题

  |                          对象初始化                          |                           循环依赖                           |
  | :----------------------------------------------------------: | :----------------------------------------------------------: |
  | ![bean初始化](https://sheungxin.github.io/notpic/20170912091609918) | ![img](https://sheungxin.github.io/notpic/b7fd5266d01609240b215e97c00254fce7cd34c5.jpeg) |

  为了解决单例情况下循环依赖，需要在实例化后，即填充属性之前提前暴露对象引用，所以Spring引入了三级缓存解决该问题，如下所示：

  ```java
  /** Cache of singleton objects: bean name --> bean instance */
  private final Map<String, Object> singletonObjects = new ConcurrentHashMap<String, Object>(256);
  
  /** Cache of early singleton objects: bean name --> bean instance */
  private final Map<String, Object> earlySingletonObjects = new HashMap<String, Object>(16);
  
  /** Cache of singleton factories: bean name --> ObjectFactory */
  private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<String, ObjectFactory<?>>(16);
  ```

  **为什么不能一级缓存？**

  已就绪的bean和未就绪的bean放在同一个map里，其他线程有可能拿到未就绪的bean，由于属性不完整导致空指针

  **为什么不能二级缓存？**

  二级缓存：若提前暴露bean引用到earlySingletonObjects中，暴露的引用是原生bean的引用。但是在有AOP的情形下，最后会对原生bean通过后置处理器AnnotationAwareAspectJAutoProxyCreator生成代理对象。其他线程有可能在代理对象生成前拿到原生对象引用，AOP失效，Spring会抛出异常。

  **三级缓存时如何处理的？**

  ```java
  public abstract class AbstractAutowireCapableBeanFactory extends AbstractBeanFactory 
      implements AutowireCapableBeanFactory {
      
      protected Object doCreateBean(final String beanName, final RootBeanDefinition mbd, final Object[] args) {
          ...
          // 先放入第三级缓存中，放入的是一个工厂bean
      	addSingletonFactory(beanName, new ObjectFactory<Object>() {
              @Override
              public Object getObject() throws BeansException {
                  // 工厂bean获取最终实例通过以下方法
                  return getEarlyBeanReference(beanName, mbd, bean);
              }
          });
          ...
          if (earlySingletonExposure) {
              // 第一、二级缓存不存在，会到第三季缓存singletonFactories.get(beanName)拿到代理后的对象
  			Object earlySingletonReference = getSingleton(beanName, false);
  			if (earlySingletonReference != null) {
                  // 若存在循环依赖，后置处理器中不会创建代理对象，返回的还是原始对象，这里需要把exposedObject改为代理对象
  				if (exposedObject == bean) {
                      // 最终替换为代理后的bean
  					exposedObject = earlySingletonReference;
  				}
          ...
      }
         
      protected Object getEarlyBeanReference(String beanName, RootBeanDefinition mbd, Object bean) {
  		Object exposedObject = bean;
          // 存在InstantiationAwareBeanPostProcessor，即需要进行代理
  		if (bean != null && !mbd.isSynthetic() && hasInstantiationAwareBeanPostProcessors()) {
  			for (BeanPostProcessor bp : getBeanPostProcessors()) {
                  // AOP后置处理器AnnotationAwareAspectJAutoProxyCreator就是一个SmartInstantiationAwareBeanPostProcessor
  				if (bp instanceof SmartInstantiationAwareBeanPostProcessor) {
  					SmartInstantiationAwareBeanPostProcessor ibp = (SmartInstantiationAwareBeanPostProcessor) bp;
  					// 对应AbstractAutoProxyCreator.getEarlyBeanReference()
                      exposedObject = ibp.getEarlyBeanReference(exposedObject, beanName);
  					if (exposedObject == null) {
  						return null;
  					}
  				}
  			}
  		}
  		return exposedObject;
  	}
  }
  
  public abstract class AbstractAutoProxyCreator extends ProxyProcessorSupport 
      implements SmartInstantiationAwareBeanPostProcessor, BeanFactoryAware {
   
  	public Object getEarlyBeanReference(Object bean, String beanName) throws BeansException {
          Object cacheKey = this.getCacheKey(bean.getClass(), beanName);
          if (!this.earlyProxyReferences.contains(cacheKey)) {
              this.earlyProxyReferences.add(cacheKey);
          }
  		// 若先postProcessAfterInitialization执行，会创建代理类，前者不再调用
          return this.wrapIfNecessary(bean, beanName, cacheKey);
      }
  }
  ```

  由上述代码可以得出大致流程如下：

  - 在bean A创建后（仅实例化，未设置属性），把bean对象A的引用包装在一个工厂类中，放入第三级缓存中
  - 若属性填充时存在循环依赖，getBean(A)由于在第一、二级缓存都找不到，会调用第三级缓存，执行工厂类的getObject。若bean A上存在SmartInstantiationAwareBeanPostProcessor（AOP），调用其getEarlyBeanReference，创建代理对象并返回
  - initializeBean中后置处理时，就不再生成代理对象，直接返回原始对象
  - 最后到缓存获取，对比当前暴露的对象是否为原始对象，若是直接改为缓存中代理对象

  **总结：本来我在初始化完成后才会生成代理对象并暴露出去，但既然你非要提前引用，怎么办呢？你要用就自己先生成一个代理对象，我后面就不再生成也用你的就可以了。**

  > 参考：https://www.cnblogs.com/grey-wolf/p/13034371.html#_label2

## xxxAware

```java
package org.springframework.beans.factory;

public interface Aware {

}
```

Aware 翻译过来可以理解为"察觉的；注意到的；感知的" ，XxxxAware 也就是对....感知的。默认情况下，Spring 的依赖注入使所有的 Bean 对 Spring 容器的存在是没有意识的，同样也就无法直接调用Spring所提供的资源。如果必须使用，就可以让 Bean 主动意识到 Spring 容器的存在，这就是 Spring Aware，实现了对Spring容器中资源的感知，如何感知的呢？

```java
package com.baomidou.ant.sys.test;

import org.springframework.beans.factory.BeanNameAware;
import org.springframework.stereotype.Component;

@Component(value = "myBeanNameAwareDemo")
public class BeanAwareDemo implements BeanNameAware {

    private String beanName;

    @Override
    public void setBeanName(String beanName) {
        System.out.println("MyBeanName-setBeanName:" + beanName);
        this.beanName = beanName;
    }

    public String getBeanName() {
        return beanName;
    }

}
```

**实现了接口中的setBeanName()方法，其它Aware类似，实现了对应的setXXX方法，在bean实例化并依赖注入完成后，由容器依次执行Aware实现的setXXX方法，这样bean就可以获取到Spring容器的相关资源**

Spring Aware 是 Spring 设计为框架内部使用的，一般不建议使用，会造成业务Bean和 Spring 框架耦合，常见的Spring Aware接口如下：

| Aware子接口                    | 描述                                           |
| :----------------------------- | :--------------------------------------------- |
| BeanNameAware                  | 获取容器中 Bean 的名称                         |
| BeanFactoryAware               | 获取当前 BeanFactory ，可以调用容器的服务      |
| ApplicationContextAware        | 获取当前ApplicationContext，可以调用容器的服务 |
| MessageSourceAware             | 获取 MessageSource 相关文本信息                |
| ApplicationEventPublisherAware | 发布事件                                       |
| ResourceLoaderAware            | 获取资源加载器，获取外部资源文件               |
| BeanClassLoaderAware           | 获取当前Bean的类加载器                         |

## BeanPostProcessor

```java
/**
 * Factory hook that allows for custom modification of new bean instances &mdash; -- 允许自定义修改新的bean实例
 * for example, checking for marker interfaces or wrapping beans with proxies. -- 接口标记或者通过代理对bean包装
 * ...
 */
public interface BeanPostProcessor {

	@Nullable
	default Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
		return bean;
	}
    
    @Nullable
	default Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
		return bean;
	}

}
```

“Factory hook”，直译为工厂钩子。hook在windows程序中是一种很常见的机制，能拦截特定的消息，由hook程序先处理，然后交给指定的窗口处理程序，一种拦截器和监听器的概念，处理特定的事件和消息。

BeanPostProcessor就是这样一种定位，它允许用户修改或包装代理一个新的bean实例，示例如下：

```java
@Component
public class MyBeanPostProcessor implements BeanPostProcessor {

    /**
    * xxxAware感知器执行完后执行
    */
    @Override
    public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
        // 匹配需要处理的bean
        if(bean instanceof BeanAwareDemo) {
            // 此处仅打印输出，可根据实际业务场景对bean进行调整
            System.out.println("start--------------"+ beanName);
        }
        return bean;
    }

    /**
    * bean回收前优先执行
    */
    @Override
    public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
        // 匹配需要处理的bean
        if(bean instanceof BeanAwareDemo) {
            // 此处仅打印输出，可根据实际业务场景进行资源释放
            System.out.println("end--------------"+ beanName);
        }
        return bean;
    }
}
```

**常见的BeanPostProcessor接口子类：**

- InstantiationAwareBeanPostProcessor

继承于BeanPostProcessor，从类名可以看出是bean实例化时感知的钩子。**当spring做好所有的准备，解析好了beanName、class等属性之后，准备实例化这个bean的时候，会先调用这个钩子**。在createBean方法里面有个resolveBeforeInstantiation方法，如下所示：

```java
	@Override
	protected Object createBean(String beanName, RootBeanDefinition mbd, Object[] args) throws BeanCreationException {
		// Give BeanPostProcessors a chance to return a proxy instead of the target bean instance.
        Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
        if (bean != null) {
            // 不为空就直接返回了
            return bean;
        }
        //省略....
        Object beanInstance = doCreateBean(beanName, mbdToUse, args);
        return beanInstance;
	}
```

上面代码里面看到，在执行doCreateBean之前先执行resolveBeforeInstantiation方法（检测InstantiationAwareBeanPostProcessor并执行），不为空就直接返回代理对象，不再执行后续的bean初始化流程。

```java
@Component
public class MyInstantiationAwareBeanPostProcessor implements InstantiationAwareBeanPostProcessor {
    
    /**
    * AbstractAutowireCapableBeanFactory.createBean中给出了一句注释
    * "Give BeanPostProcessors a chance to return a proxy instead of the target bean instance"
    * 即可以创建代理对象替代原始的bean，AOP中AnnotationAwareAspectJAutoProxyCreator就是它的一个子类
    */
    @Override
    public Object postProcessBeforeInstantiation(Class<?> beanClass, String beanName) throws BeansException {
        if(beanClass == BeanAwareDemo.class) {
            // 此处仅打印输出
            System.out.println("start2--------------"+ beanName);
        }
        return null;
    }

    /**
    * postProcessBeforeInstantiation返回不为空执行
    */
    @Override
    public boolean postProcessAfterInstantiation(Object bean, String beanName) throws BeansException {
        if(bean instanceof BeanAwareDemo) {
            System.out.println("end2--------------"+ beanName);
        }
        return true;
    }
}
```

官方不建议使用，只适用于Spring框架内部使用（参见类头部注释），推荐使用BeanPostProcessor、InstantiationAwareBeanPostProcessorAdapter

- MergedBeanDefinitionPostProcessor

继承于BeanPostProcessor，**当bean的实例被创建，但是属性还没有被初始化的时候调用**，参见源码：AbstractAutowireCapableBeanFactory.doCreateBean。从其子类AutowiredAnnotationBeanPostProcessor、ScheduledAnnotationBeanPostProcessor可以看出，**MergedBeanDefinitionPostProcessor的作用是对bean进行功能上的增强，比如处理自动注入、JMS、定时器等注解，获取元数据信息，用于后续使用**

- SmartInstantiationAwareBeanPostProcessor

继承于接口InstantiationAwareBeanPostProcessor，新增了以下三个方法对其进行了增强，不建议使用，只适用于Spring框架内部使用

```java
/**
 * Extension of the {@link InstantiationAwareBeanPostProcessor} interface,
 * adding a callback for predicting the eventual type of a processed bean.
 *
 * <p><b>NOTE:</b> This interface is a special purpose interface, mainly for
 * internal use within the framework. In general, application-provided
 * post-processors should simply implement the plain {@link BeanPostProcessor}
 * interface or derive from the {@link InstantiationAwareBeanPostProcessorAdapter}
 * class. New methods might be added to this interface even in point releases.
 */
public interface SmartInstantiationAwareBeanPostProcessor extends InstantiationAwareBeanPostProcessor {

	/**
	 * 感知最终的bean类型
	 * Predict the type of the bean to be eventually returned from this
	 * processor's {@link #postProcessBeforeInstantiation} callback.
	 * <p>The default implementation returns {@code null}.
	 */
	@Nullable
	default Class<?> predictBeanType(Class<?> beanClass, String beanName) throws BeansException {
		return null;
	}

	/**
	 * 确定bean的构造函数 
	 * Determine the candidate constructors to use for the given bean.
	 * <p>The default implementation returns {@code null}.
	 */
	@Nullable
	default Constructor<?>[] determineCandidateConstructors(Class<?> beanClass, String beanName)
			throws BeansException {
		return null;
	}

	/**
	 * 获取bean的早期访问引用，用于解析单例bean的循环依赖问题
	 * Obtain a reference for early access to the specified bean,
	 * typically for the purpose of resolving a circular reference.
	 * <p>This callback gives post-processors a chance to expose a wrapper
	 * early - that is, before the target bean instance is fully initialized.
	 */
	default Object getEarlyBeanReference(Object bean, String beanName) throws BeansException {
		return bean;
	}

}
```

AOP中的后置处理器AnnotationAwareAspectJAutoProxyCreator，就是通过实现SmartInstantiationAwareBeanPostProcessor接口实现的

以上三个BeanPostProcessor三个子类均起着“钩子”的作用，启用时机不同而已。除此之外，还有一个比较类似的接口**BeanFactoryPostProcessor**，允许用户自定义修改应用中注册的bean（注意是已加载但未初始化的bean）

```java
@Component
public class BeanAwareDemo {
    private Integer id;
    private String name;

    public BeanAwareDemo() {
        // 有有参构造函数后不执行，如果没有id、name均为null
        System.out.println("****************" + id + "," + name);
    }

    public BeanAwareDemo(Integer id) {
        // postProcessBeanFactory中注入了参数id的值
        this.id = id;
        // id不为空，此时name为null
        System.out.println("###############" + id + "," + name);
    }

    public void display() {
        // id、name均有值，name在构造函数执行后注入了postProcessBeanFactory中设置的值
        System.out.println(id + "," + name);
    }

    public void setName(String name) {
        this.name = name;
    }
}

@Component
public class MyBeanFactoryPostProcessor implements BeanFactoryPostProcessor {

    /*
    * 解析完配置文件或者注解，并初始化bean工厂后执行，可见源码AbstractApplicationContext中refresh()
    */
    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) throws BeansException {
        BeanDefinition beanDefinition = beanFactory.getBeanDefinition("beanAwareDemo");
        // 修改已注册bean的构造函数中参数
        beanDefinition.getConstructorArgumentValues().addGenericArgumentValue(new Random().nextInt());
        // 修改已注册bean的属性
        beanDefinition.getPropertyValues().add("name",new Random().nextInt());
        // 也可以生成一个代理对象注册到BeanFactory中，参考：https://www.cnblogs.com/piepie/p/9061076.html
    }
}

@SpringBootTest
public class BeanFactoryPostProcessorTest {

    @Autowired
    private BeanAwareDemo beanAwareDemo;

    @Test
    public void test(){
        beanAwareDemo.display();
    }

}
```

根据上面实例可以看出，实现接口BeanFactoryPostProcessor可以得到beanFactory，我们可以根据业务需要，在容器实例化任何其他的bean前修改其配置元数据，可以配置多个，通过”order”控制执行次序即可(要实现Ordered接口)

> 参考：https://blog.csdn.net/qq_24689783/article/details/103577928

# AOP

> 在软件业，AOP为Aspect Oriented Programming的缩写，意为：面向切面编程，通过预编译方式和运行期动态代理实现程序功能统一维护的一种技术。AOP是OOP(面向对象程序设计)的延续，是软件开发中的一个 热点，也是Spring框架中的一个重要内容，是函数式编程的一种衍生范型。利用AOP可以对业务逻辑的各个部分进行隔离，从而使得业务逻辑各部分之间的耦合度降低，提高程序的可重用性，同时提高了开发的效率。

## 基础概念

<img src="https://sheungxin.github.io/notpic/2019120223045810.png" alt="在这里插入图片描述" style="zoom:50%;" />

1. Joinpoint：连接点，对应上图贷款申请、贷款管理、入出金管理等业务，在程序中的表现就是一个方法，***在代码中所谓的Joinpoint指的就是我们的方法，是允许申明切入点和通知的地方***。
2. Pointcut：切入点，***针对Joinpoint进行一定的逻辑关联，声明Advice发生的地方***。比如说上图Pointcut声明了贷款申请、贷款管理、入出金管理业务会做日志增强处理。假如再来一个还贷管理，由于还没有声明，则不会进行增强处理
3. Advice：通知，即针对满足Pointcut的地方做增强处理
4. Aspect：切面，***就是关注节点的模块化***，是Pointcut和Advice的集合
5. Target：目标，是***真正逻辑实现的地方，被织入的类***
6. Proxy：代理，***将切面应用于目标对象生成的代理对象***
7. Weaving：织入，这是一个很重要的概念，它指的是**将切面应用于目标对象生成代理对象的过程**

## Spring中实现

![在这里插入图片描述](https://sheungxin.github.io/notpic/20191204192626305.png)

**根据上图可以看出，最终在spring容器中注册了一个AnnotationAwareAspectJAutoProxyCreator对象。而AnnotationAwareAspectJAutoProxyCreator是SmartInstantiationAwareBeanPostProcessor的实现类，结合上文Bean生命周期中hook触发时机，大概就可以想象出对象初始化后创建了一个代理对象。**

重点关注postProcessBeforeInitialization和postProcessAfterInitialization这两个方法，这两个方法是在它的父类AbstractAutoProxyCreator中实现的，postProcessBeforeInitialization没有做任何处理，主要的逻辑都在postProcessAfterInitialization中，如下所示：

```java
public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
	if (bean != null) {
		//构建一个key
		Object cacheKey = this.getCacheKey(bean.getClass(), beanName);
		//如果需要被代理，那么就进行代理处理
		if (this.earlyProxyReferences.remove(cacheKey) != bean) {
			//创建代理类的核心逻辑所在
			return this.wrapIfNecessary(bean, beanName, cacheKey);
		}
	}
	return bean;
}
...
protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
	//已经创建代理的bean不需要再创建
	if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
		return bean;
	//不需要创建代理的bean直接跳过
	} else if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
		return bean;
	//如果不是基础设施类或者需要跳过的类，那么就需要创建代理类
	} else if (!this.isInfrastructureClass(bean.getClass()) && !this.shouldSkip(bean.getClass(), beanName)) {
		//关键代码，获取被增强的方法，如果有就创建代理
		Object[] specificInterceptors = this.getAdvicesAndAdvisorsForBean(bean.getClass(), beanName, (TargetSource)null);
		if (specificInterceptors != DO_NOT_PROXY) {
			//添加如缓存
			this.advisedBeans.put(cacheKey, Boolean.TRUE);
			//创建代理类
			Object proxy = this.createProxy(bean.getClass(), beanName, specificInterceptors, 
                                            new SingletonTargetSource(bean));
			//将代理放入缓存
			this.proxyTypes.put(cacheKey, proxy.getClass());
			return proxy;
		} else {
			this.advisedBeans.put(cacheKey, Boolean.FALSE);
			return bean;
		}
	} else {
		this.advisedBeans.put(cacheKey, Boolean.FALSE);
		return bean;
	}
}

```

- 流程图如下：

![在这里插入图片描述](https://sheungxin.github.io/notpic/20191204234632520.png)

- JDK动态代理和CGLIB动态代理有什么区别
  - JDK动态代理只能创建接口代理，不能为类创建代理
  - CGLIB代理的方法不能用final修饰，因为其动态为代理对象创建子类，会覆盖父类的方法，final方法不能被重写

- 什么情况下会使用JDK动态代理和CGLIB代理
  - 当类实现了接口的时候，默认使用的是JDK的动态代理
  - 当类实现了接口，可以强制使用CGLIB动态代理 
  - 当类没有实现接口，则强制使用CGLIB动态代理

> 参考：https://blog.csdn.net/qq_24689783/article/details/103340012

# 事务

## 事务传播性

Spring中事务传播行为通过Transactional的propagation属性来指定，传播行为如下：

- PROPAGATION_REQUIRED：支持当前事务，假设当前没有事务，就新建一个事务，默认传播行为
- PROPAGATION_SUPPORTS：支持当前事务，假设当前没有事务，就以非事务方式运行
- PROPAGATION_MANDATORY：支持当前事务，假设当前没有事务，就抛出异常
- PROPAGATION_REQUIRES_NEW：新建事务，假设当前存在事务，把当前事务挂起
- PROPAGATION_NOT_SUPPORTED：以非事务方式运行操作，假设当前存在事务，就把当前事务挂起
- PROPAGATION_NEVER：以非事务方式运行，假设当前存在事务，则抛出异常
- PROPAGATION_NESTED：如果当前存在事务，则在嵌套事务内执行。如果当前没有事务，则进行与PROPAGATION_REQUIRED类似的操作

PROPAGATION_REQUIRED、PROPAGATION_REQUIRES_NEW、PROPAGATION_NESTED三者的区别？

- REQUIRES_NEW在父级方法中调用，开启新的事务，回滚与否只与子方法有关，父级方法进行捕获异常操作后，可以防止父级方法回滚
- REQUIRED 在父级方法中调用，沿用父级事务，如果子方法抛出异常，无论父级方法是否捕获，都会引起父级与子方法的回滚，因为他们属于一个事务，事务切面同时监控两个方法，出现异常即回滚。同理，父方法抛出异常，也会造成子方法回滚，REQUIRES_NEW则不会
- NESTED如果子方法无异常、父级方法出现异常，子方法与父级方法都会回滚。但如果子方法出现异常，子方法必然回滚，父方法回滚取决于父级方法是否进行捕获异常（这点和REQUIRES_NEW类似）

## 事务的回滚规则

**通常情况下，如果在事务中抛出了未检查异常（继承自 RuntimeException 的异常），则默认将回滚事务。如果没有抛出任何异常，或者抛出了已检查异常，则仍然提交事务**。这通常也是大多数开发者希望的处理方式，也是 EJB（Enterprise Java Beans）中的默认处理方式。但是，我们可以根据需要人为控制事务在抛出某些未检查异常时任然提交事务，或者在抛出某些已检查异常时回滚事务。

```java
指定单一异常类：@Transactional(rollbackFor=RuntimeException.class)
指定多个异常类：@Transactional(rollbackFor={RuntimeException.class, Exception.class})
```

## 事务失效

- 数据库引擎不支持事务，以 MySQL 为例，其 MyISAM 引擎不支持事务操作

- 没有被 Spring 管理，如下所示：

  ```java
  // @Service
  public class OrderServiceImpl implements OrderService {   
   	
      @Transactional    
  	public void updateOrder(Order order) {       
   		// update order
    	}
  }
  ```

- 方法不是 public的， Spring 官方文档如下

    > When using proxies, you should apply the **@Transactional annotation only to methods with public visibility**. If you do annotate protected, private or package-visible methods with the @Transactional annotation, no error is raised, but the annotated method does not exhibit the configured transactional settings. Consider the use of AspectJ (see below) if you need to annotate non-public methods.

  ```java
@Service
  public class DemoServiceImpl implements  DemoService {
  
      @Transactional(rollbackFor = SQLException.class)
      @Override
  	int saveAll(){  // 编译器一般都会在这个地方给出错误提示
  		// do someThing;
          return  1;
      }
  }
  ```
  
  ![img](https://sheungxin.github.io/notpic/16925604-6a3b64f1e768de66.png)

- **自身调用问题**

  - 示例一：

  ```java
  @Service
  public class OrderServiceImpl implements OrderService {
      
      public void update(Order order) {
          updateOrder(order);
      }
      
      @Transactional
      public void updateOrder(Order order) {
          // update order；
      }
  }
  ```

  update方法上面没有加 `@Transactional` 注解，调用有 `@Transactional` 注解的 updateOrder 方法，updateOrder 方法上的事务管用吗？

  - 示例二：

  ```java
  @Service
  public class OrderServiceImpl implements OrderService {
      
      @Transactional
      public void update(Order order) {
          updateOrder(order); 
  	}
      
      @Transactional(propagation = Propagation.REQUIRES_NEW)
      public void updateOrder(Order order) {
          // update order；
      }
  }
  ```

  这次在 update 方法上加了 `@Transactional`，updateOrder 加了 `REQUIRES_NEW` 新开启一个事务，那么新开的事务管用么？

  这两个例子的答案是：不管用！

  因为它们发生了自身调用，就调该类自己的方法，而没有经过 Spring 的代理类，默认只有在外部调用事务才会生效，这也是老生常谈的经典问题了。

  这个的解决方案之一就是在的类中注入自己，用注入的对象再调用另外一个方法，这个不太优雅，另外一个可行的方案可以参考《[Spring 如何在一个事务中开启另一个事务？](https://links.jianshu.com/go?to=https%3A%2F%2Fmp.weixin.qq.com%2Fs%3F__biz%3DMzI3ODcxMzQzMw%3D%3D%26mid%3D2247491775%26idx%3D2%26sn%3D142f1d6ab0415f17a413a852efbde54f%26scene%3D21%23wechat_redirect)》这篇文章。

- 数据源没有配置事务管理器

  ```java
  @Bean
  public PlatformTransactionManager transactionManager(DataSource dataSource) {
      return new DataSourceTransactionManager(dataSource);
  }
  ```

  如上面所示，当前数据源若没有配置事务管理器，那也是白搭！

- 不支持事务

  ```java
  @Service
  public class OrderServiceImpl implements OrderService {
      
      @Transactional
      public void update(Order order) {
          updateOrder(order);
      }
      
      @Transactional(propagation = Propagation.NOT_SUPPORTED)
      public void updateOrder(Order order) {
          // update order；
      }
  }
  ```

  **Propagation.NOT_SUPPORTED：** 表示不以事务运行，当前若存在事务则挂起

- **异常被吃了**

  ```java
  @Service
  public class OrderServiceImpl implements OrderService {
      
      @Transactional
      public void updateOrder(Order order) {
          try {
              // update order;
           }catch (Exception e){
              //do something;
          }
      }
  }
  ```

- **异常类型错误或格式配置错误**

  ```java
  @Service
  public class OrderServiceImpl implements OrderService {
      
  	@Transactional
      // @Transactional(rollbackFor = SQLException.class)
      public void updateOrder(Order order) {
          try {            
          	// update order
          }catch (Exception e){
             throw new Exception("更新错误");        
          }    
      }
  }
  ```

  这样事务也是不生效的，因为默认回滚的是：RuntimeException，如果你想触发其他异常的回滚，需要在注解上配置一下，如：

  ```ruby
  @Transactional(rollbackFor = Exception.class)
  ```

  这个配置仅限于 `Throwable` 异常类及其子类

# FactoryBean

一般情况下，Spring通过反射机制利用<bean>的class属性指定实现类实例化Bean。在某些情况下，实例化Bean过程比较复杂，如果按照传统的方式，则需要在<bean>中提供大量的配置信息（不局限此类场景，可参考Spring中使用场景）。配置方式的灵活性是受限的，这时采用编码的方式可能会得到一个简单的方案。Spring为此提供了一个org.springframework.bean.factory.FactoryBean的工厂类接口，用户可以通过实现该接口定制实例化Bean的逻辑。FactoryBean接口对于Spring框架来说占用重要的地位，Spring自身就提供了70多个FactoryBean的实现。它们隐藏了实例化一些复杂Bean的细节，给上层应用带来了便利。从Spring3.0开始，FactoryBean开始支持泛型，即接口声明改为FactoryBean<T>的形式

以Bean结尾，表示它是一个Bean，不同于普通Bean的是：它是实现了FactoryBean<T>接口的Bean，根据该Bean的ID从BeanFactory中获取的实际上是FactoryBean的getObject()返回的对象，而不是FactoryBean本身，如果要获取FactoryBean对象，请在id前面加一个&符号来获取。

```java
import org.springframework.beans.factory.FactoryBean;

public class CarFactoryBean implements FactoryBean<Car> {
    private String carInfo;

    public Car getObject() throws Exception {
        Car car = new Car();
        String[] infos = carInfo.split(",");
        car.setBrand(infos[0]);
        car.setMaxSpeed(Integer.valueOf(infos[1]));
        car.setPrice(Double.valueOf(infos[2]));
        return car;
    }

    public Class<Car> getObjectType() {
        return Car.class;
    }

    public boolean isSingleton() {
        return false;
    }

    public String getCarInfo() {
        return this.carInfo;
    }

    // 接受逗号分割符设置属性信息  
    public void setCarInfo(String carInfo) {
        this.carInfo = carInfo;
    }
}
```



# 优雅使用

- [Spring Boot 统一数据格式](https://dayarch.top/p/spring-boot-global-return.html)

- [Spring 数据绑定机制](https://www.cnblogs.com/FraserYu/p/12047279.html)
- [消除项目中丑陋的Try Catch](https://mp.weixin.qq.com/s/6vtKzFye77M9pZSQttyBRg)

- [事务诡异事件分析](https://mp.weixin.qq.com/s?__biz=MzAxMjEwMzQ5MA==&mid=2448888540&idx=2&sn=638239681c7c5d84ae5e16580ffa5f92&chksm=8fb548f1b8c2c1e7ad8fc94dfab856f951d0802af35f896f19a2801e48b0098a4e39ab2edde0&scene=21#wechat_redirect)

- [SpringBoot + MyBatis + MySQL读写分离实践](https://mp.weixin.qq.com/s/RdI1oGi5So3Y4-QzBPXjLQ)

