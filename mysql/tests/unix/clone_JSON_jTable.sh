. env/setEnvironment.sh
export DIR=JSON/$JSON
export MDIR=$TESTDATA/$JSON
export SCHEMA=JTEST
export FILENAME=testcase
export SCHVER=1
mkdir -p $DIR
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f <../sql/JSON_IMPORT.sql >$LOGDIR/install/JSON_IMPORT.log
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f --init-command="set @SCHEMA='$SCHEMA'; set @ID=$SCHVER; set @METHOD='JSON_TABLE'" <sql/RECREATE_SCHEMA.sql >>$LOGDIR/RECREATE_SCHEMA.log
node ../node/jTableImport  --username=$DB_USER --hostname=$DB_HOST --password=$DB_PWD  --port=$DB_PORT --database=$DB_DBNAME  file=$MDIR/$FILENAME.json toUser="$SCHEMA$SCHVER"
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT --init-command="set @SCHEMA='$SCHEMA'; set @ID1=''; set @ID2=$SCHVER; set @METHOD='JSON_TABLE'" --table  <sql/COMPARE_SCHEMA.sql >>$LOGDIR/COMPARE_SCHEMA.log
node ../node/export  --username=$DB_USER --hostname=$DB_HOST --password=$DB_PWD  --port=$DB_PORT --database=$DB_DBNAME  file=$DIR/${FILENAME}$SCHVER.json owner="$SCHEMA$SCHVER" mode=$MODE  logFile=$EXPORTLOG
export SCHVER=2
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT -v -f --init-command="set @SCHEMA='$SCHEMA'; set @ID=$SCHVER; set @METHOD='JSON_TABLE'" <sql/RECREATE_SCHEMA.sql >>$LOGDIR/RECREATE_SCHEMA.log
node ../node/jTableImport  --username=$DB_USER --hostname=$DB_HOST --password=$DB_PWD  --port=$DB_PORT --database=$DB_DBNAME  file=$DIR/${FILENAME}1.json toUser="$SCHEMA$SCHVER"
mysql -u$DB_USER -p$DB_PWD -h$DB_HOST -D$DB_DBNAME -P$DB_PORT --init-command="set @SCHEMA='$SCHEMA'; set @ID1=1; set @ID2=$SCHVER; set @METHOD='JSON_TABLE'" --table  <sql/COMPARE_SCHEMA.sql >>$LOGDIR/COMPARE_SCHEMA.log
node ../node/export  --username=$DB_USER --hostname=$DB_HOST --password=$DB_PWD  --port=$DB_PORT --database=$DB_DBNAME  file=$DIR/${FILENAME}$SCHVER.json owner="$SCHEMA$SCHVER" mode=$MODE  logFile=$EXPORTLOG
node ../../utilities/compareFileSizes $LOGDIR $MDIR $DIR
node ../../utilities/compareArrayContent $LOGDIR $MDIR $DIR false
