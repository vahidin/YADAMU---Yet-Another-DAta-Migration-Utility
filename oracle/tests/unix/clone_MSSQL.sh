. env/setEnvironment.sh
export DIR=JSON/$MSSQL
export MDIR=$TESTDATA/$MSSQL 
export SCHVER=1
export SCHEMA=ADVWRK
export FILENAME=AdventureWorks
mkdir -p $DIR
sqlplus $DB_USER/$DB_PWD@$DB_CONNECTION @../sql/COMPILE_ALL.sql $LOGDIR 
sqlplus $DB_USER/$DB_PWD@$DB_CONNECTION @sql/RECREATE_SCHEMA.sql $LOGDIR  $SCHEMA $SCHVER Clarinet
sh unix/import_MSSQL_ALL.sh $MDIR $SCHEMA $SCHVER "" 
node ../node/export userid=$DB_USER/$DB_PWD@$DB_CONNECTION  file=$DIR/$FILENAME$SCHVER.json owner=\"$SCHEMA$SCHVER\" mode=$MODE  logfile=$EXPORTLOG
export SCHVER=2
sqlplus $DB_USER/$DB_PWD@$DB_CONNECTION @sql/RECREATE_SCHEMA.sql $LOGDIR  $SCHEMA $SCHVER Clarinet
node ../node/import userid=$DB_USER/$DB_PWD@$DB_CONNECTION  file=$DIR/${FILENAME}1.json toUser=\"$SCHEMA$SCHVER\" mode=$MODE logfile=$IMPORTLOG
sqlplus $DB_USER/$DB_PWD@$DB_CONNECTION @sql/COMPARE_SCHEMA.sql $LOGDIR  $SCHEMA 1 2 Clarinet $MODE
node ../node/export userid=$DB_USER/$DB_PWD@$DB_CONNECTION  file=$DIR/$FILENAME$SCHVER.json owner=\"$SCHEMA$SCHVER\" mode=$MODE  logfile=$EXPORTLOG
node ../../utilities/compareFileSizes $LOGDIR $MDIR $DIR
node ../../utilities/compareArrayContent $LOGDIR $MDIR $DIR false