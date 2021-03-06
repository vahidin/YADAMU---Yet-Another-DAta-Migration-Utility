call env\setEnvironment.bat
@set DIR=JSON\%MSSQL%
@set MDIR=%TESTDATA%\%MSSQL%
@set SCHEMAVER=1
mkdir %DIR%
mysql -u%DB_USER% -p%DB_PWD% -h%DB_HOST% -D%DB_DBNAME% -P%DB_PORT% -v -f <..\sql\SCHEMA_COMPARE.sql >%LOGDIR%\install\SCHEMA_COMPARE.log
mysql -u%DB_USER% -p%DB_PWD% -h%DB_HOST% -D%DB_DBNAME% -P%DB_PORT% -v -f --init-command="set @ID=%SCHEMAVER%; set @METHOD='Clarinet'" <sql\RECREATE_MSSQL_ALL.sql >>%LOGDIR%\RECREATE_SCHEMA.log
call windows\import_MSSQL.bat %MDIR% %SCHEMAVER% ""
call windows\export_MSSQL %DIR% %SCHEMAVER% %SCHEMAVER%
@set SCHEMAVER=2
mysql -u%DB_USER% -p%DB_PWD% -h%DB_HOST% -D%DB_DBNAME% -P%DB_PORT% -v -f --init-command="set @ID=%SCHEMAVER%; set @METHOD='Clarinet'" <sql\RECREATE_MSSQL_ALL.sql >>%LOGDIR%\RECREATE_SCHEMA.log
call windows\import_MSSQL.bat %DIR% %SCHEMAVER% 1
mysql -u%DB_USER% -p%DB_PWD% -h%DB_HOST% -D%DB_DBNAME% -P%DB_PORT% --init-command="set @ID1=1; set @ID2=2; set @METHOD='Clarinet'" --table  <sql\COMPARE_MSSQL_ALL.sql >>%LOGDIR%\COMPARE_SCHEMA.log
call windows\export_MSSQL %DIR% %SCHEMAVER% %SCHEMAVER%
node ..\..\utilities\compareFileSizes %LOGDIR% %MDIR% %DIR%
node ..\..\utilities\compareArrayContent %LOGDIR% %MDIR% %DIR% false