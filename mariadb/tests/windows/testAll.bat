cls
call env\setEnvironment.bat
mkdir logs
rmdir /s /q %LOGDIR%
mkdir %LOGDIR%
mkdir %LOGDIR%\install
@set MODE=DATA_ONLY
call windows\clone_JSON.bat
call windows\clone_MYSQL.bat
call windows\clone_Oracle.bat 
call windows\clone_MSSQL_ALL.bat
call windows\clone_MSSQL.bat
@set MODE=DDL_AND_DATA
call windows\clone_Oracle.bat