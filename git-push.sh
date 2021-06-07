stty -echo
 
echo ¿¿¿¿¿¿$(pwd)
echo 

echo ¿¿¿¿¿¿¿git add .
git add .
echo;
 
set /p declation=¿¿¿¿¿commit¿¿
git commit -m "%declation%"
echo;
 
echo ¿¿¿¿¿¿¿¿¿¿¿¿¿git push origin master
git push origin master
echo;
 
echo ¿¿¿¿
echo;
