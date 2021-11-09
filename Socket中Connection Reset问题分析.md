# 现象描述
先后启动服务端和客户端，客户端正常执行完毕，服务端出现Connection Reset异常，错误定位在**while ((bufferSize = is.read(bytes))!=-1)**

# 服务端代码
```
import java.io.*;
import java.net.ServerSocket;
import java.net.Socket;

public class Server {
    public static void main(String[] args) throws IOException {
        ServerSocket server = new ServerSocket(55335);
        File dir = new File("received");
        if (!dir.exists()){
            dir.mkdir();
        }
        while (true){
            Socket socket = server.accept();
            new Thread(()->{
                try {
                    String name = null;
                    InputStream is = socket.getInputStream();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(is));
                    if ((name = reader.readLine())==null){
                        System.out.println("出现异常！无法完成此次传输...");
                        return;
                    }
                    System.out.println("文件名为："+name);
                    System.out.println("开始接收...");
                    File file = new File(dir,name);
                    FileOutputStream fos = new FileOutputStream(file);
                    int size = 0;
                    int bufferSize;
                    byte[] bytes = new byte[1024];
                    while ((bufferSize = is.read(bytes))!=-1){
                        System.out.println(bufferSize);
                        fos.write(bytes,0,bufferSize);
                        System.out.println("已写入"+(size+=bufferSize)+"B数据");
                    }
                    fos.flush();
                    System.out.println(bufferSize);
                    fos.close();
                    System.out.println("写入完成！路径为："+file.getAbsolutePath());
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }).start();

            OutputStream os = socket.getOutputStream();
            os.write("hello\t".getBytes());
        }
    }
}
```
服务端代码逻辑如下：
- 循环等待建立连接
- 通过字符流接收客户端发送过来的数据，作为新文件的文件名
- 通过字节流接收客户端发送过来的数据，并写入指定文件

# 客户端代码
```
import java.io.*;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Scanner;

public class Client {
    public static void main(String[] args) throws IOException, InterruptedException {
        Scanner sc = new Scanner(System.in);
        byte[] bytes = new byte[1024];
        String path;
        File file;
        System.out.println("输入文件路径：");
        path = sc.nextLine();
        file = new File(path);
        System.out.println("路径为："+file.getAbsolutePath());
        System.out.println("文件大小："+file.length()+"B");
        if (!file.exists()){
            System.out.println("文件不存在！");
            return;
        }
        int size = 0;
        int bufferSize = 0;
        Socket socket = new Socket("localhost",55335);
        OutputStream os = socket.getOutputStream();
        os.write((file.getName()+"\n").getBytes());
        os.flush();
        FileInputStream fis = new FileInputStream(file);
        while ((bufferSize=fis.read(bytes))!=-1){
            size+=bufferSize;
            os.write(bytes);
            System.out.println("已传输"+size+"B");
        }
        os.flush();
        System.out.println("传输完成");
        Thread.sleep(1000);
    }
}
```
客户端代码逻辑如下：
- 建立socket连接
- 先通过字符流把文件名发送到服务端
- 然后通过字节流把文件内容发送到服务端

# 分析过程
- 服务端在**while ((bufferSize = is.read(bytes))!=-1)** 时Connection Reset，即服务端数据还未读取完毕，客户端已退出
- 核对客户端代码，发现发送完数据，沉睡了一秒后结束运行。正常来说，测试文件比较小，应该可以正常接收完毕。但是**客户端最后并未执行socket.shutdownOutput()，通知服务端数据已发送完毕，导致服务端一直处理读取数据状态，但由于数据一直未就绪导致服务端IO堵塞**。这时，客户端退出，服务端就异常了
- 发现上述问题，我们在客户端加上socket.shutdownOutput()，服务端正常执行完毕，验证上述结论
- 出现新的问题，服务端未接收到后续发送到的数据，本地只写入了一个空文件
- debug模式开启，在客户端**while ((bufferSize=fis.read(bytes))!=-1)** 加上断点，服务端竟然可以接收到数据。感觉有点奇怪，随后又在客户端第一次输出流os.flush()后沉睡一秒，去除断点也可以正常执行并接收到数据。看来和发送接收的时间点有关系，纠结中...
- 客户端中有两次发送数据，第一次可以接收，第二次不行。两次中间增加执行间隔，又都可以。可以得出，肯定是前一次发送对第二次造成了影响。随后，把第一次发送文件名的代码注释掉，同时注释掉服务端接收的代码，文件数据接收正常
- 观察两次写入的不同，第一次内容加上了换行符。然后再看服务端代码，第一次使用的缓存字符流，读完文件内容时使用的却是字节流，交替使用了缓冲字符流和字节流
- 这样就可以解释上述现象了，缓冲字符流读取数据时有缓存，直接转向InputStream去读取，缓存中的数据是读不到的。因为测试发送的数据量比较小，都进入了缓冲区，转换成字节流后就造成读取不到任何数据的情况。加断点或者沉睡，延缓了第二次数据发送，服务端在切换成字节流后才接收到数据，所以又可以正常接收

# 解决方案
使用字节流或者字符流，不要交替使用
- 字节流：先发送文件名占用字节数(int类型)，再发送文件名，最后发送文件内容。服务端先读取4个字节转化为int，并作为第二次读取的字节数读取文件名，最后按指定步长读取文件内容
- 字符流：逐行读取文件并发送，服务端统一为字符流读取