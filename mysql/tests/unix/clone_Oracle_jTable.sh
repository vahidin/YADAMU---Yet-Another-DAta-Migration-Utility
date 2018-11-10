export TNS=$1
export DIR=JSON/$TNS
export MODE=DATA_ONLY
export MDIR=../../JSON/$TNS/$MODE
export ID=1
mkdir -p $DIR
. ./env/connection.sh
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f <../sql/JSON_IMPORT.sql
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f --init-command="SET @ID=$ID" <sql/RECREATE_ORACLE_ALL.sql
. ./unix/import_Oracle_jTable.sh $MDIR $ID ""
. ./unix/export_Oracle.sh $DIR $ID $ID
export ID=2
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f --init-command="SET @ID=$ID" <sql/RECREATE_ORACLE_ALL.sql
. ./unix/import_Oracle_jTable.sh $DIR $ID 1
. ./unix/export_Oracle.sh $DIR $ID $ID
ls -l $DIR/*1.json
ls -l $DIR/*2.json