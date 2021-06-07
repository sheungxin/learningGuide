stty -echo
 
echo 当前目录是：$(pwd)
echo 

echo 开始添加变更：git add .
git add .
echo;
 
read -s -p "输入提交的commit信息:" declation
git commit -m "$declation%"
echo;
 
echo 将变更情况提交到远程主分支：git push origin master
git push origin master
echo;
 
echo 执行完毕
echo;
