export SRC=$1
export SCHVER=$2
export VER=$3
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/Northwind$VER.json        toUser=\"Northwind$SCHVER\"       logfile=$IMPORTLOG mode=$MODE   
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/Sales$VER.json            toUser=\"Sales$SCHVER\"           logfile=$IMPORTLOG mode=$MODE
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/Person$VER.json           toUser=\"Person$SCHVER\"          logfile=$IMPORTLOG mode=$MODE
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/Production$VER.json       toUser=\"Production$SCHVER\"      logfile=$IMPORTLOG mode=$MODE
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/Purchasing$VER.json       toUser=\"Purchasing$SCHVER\"      logfile=$IMPORTLOG mode=$MODE
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/HumanResources$VER.json   toUser=\"HumanResources$SCHVER\"  logfile=$IMPORTLOG mode=$MODE
node ../node/jTableImport  userid=$DB_USER/$DB_PWD@$DB_CONNECTION FILE=$SRC/AdventureWorksDW$VER.json toUser=\"DW$SCHVER\"              logfile=$IMPORTLOG mode=$MODE
