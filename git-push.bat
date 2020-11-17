@echo "Start submitting code to the local repository"
@echo "The current directory is£º%cd%"
git add *
@echo;
 
@echo "Commit the changes to the local repository"
set now=%date% %time%
@echo %now%
git commit -m "%now%"
@echo;
 
@echo "Commit the changes to the remote git server"
git push
@echo;
 
@echo "Batch execution complete!"
