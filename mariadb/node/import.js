"use strict"
const fs = require('fs');
const mariadb = require('mariadb');
const path = require('path');

const Yadamu = require('../../common/yadamuCore.js');
const RowParser = require('../../common/rowParser.js');
const DBWriter = require('./dbWriter.js');
const MariaCore = require('./mariaCore.js');
1
function processFile(conn, schema, importFilePath, batchSize, commitSize, mode, status, logWriter) {

  return new Promise(function (resolve,reject) {
    const dbWriter = new DBWriter(conn,schema,batchSize,commitSize,mode,status,logWriter);
    const rowGenerator = new RowParser(logWriter);
    const readStream = fs.createReadStream(importFilePath);
    dbWriter.on('finish', function() { resolve()});
    readStream.pipe(rowGenerator).pipe(dbWriter);
  })
}

async function main() {

  let pool;
  let conn;
  let parameters;

  let logWriter = process.stdout;
  let status;
  let results;

  try {

    process.on('unhandledRejection', function (err, p) {
      logWriter.write(`Unhandled Rejection:\Error:`);
      logWriter.write(`${err}\n${err.stack}\n`);
    })

    parameters = MariaCore.processArguments(process.argv,'export');
    status = Yadamu.getStatus(parameters);

    if (parameters.LOGFILE) {
      logWriter = fs.createWriteStream(parameters.LOGFILE,{flags : "a"});
    }

    const connectionDetails = {
            host      : parameters.HOSTNAME
           ,user      : parameters.USERNAME
           ,password  : parameters.PASSWORD
           ,port      : parameters.PORT ? parameters.PORT : 3307
           ,database  : parameters.DATABASE
           ,multipleStatements: true
    }

    pool = mariadb.createPool(connectionDetails);
    conn = await pool.getConnection();
    
    if (await MariaCore.setMaxAllowedPacketSize(pool,conn,status,logWriter)) {
       pool = mariadb.createPool(connectionDetails);
       conn = await pool.getConnection();
                                                           
    }     

    await MariaCore.configureSession(conn,status);
 	results = await MariaCore.createTargetDatabase(conn,status,parameters.TOUSER);
    const stats = fs.statSync(parameters.FILE)
    const fileSizeInBytes = stats.size
    logWriter.write(`${new Date().toISOString()}[Clarinet]: Processing file "${path.resolve(parameters.FILE)}". Size ${fileSizeInBytes} bytes.\n`)

    await processFile(conn, parameters.TOUSER, parameters.FILE, parameters.BATCHSIZE, parameters.COMMITSIZE, parameters.MODE, status, logWriter)
  
    await conn.end();
    await pool.end();
    Yadamu.reportStatus(status,logWriter)
  } catch (e) {
    if (logWriter !== process.stdout) {
      console.log(`Import operation failed: See "${parameters.LOGFILE}" for details.`);
      logWriter.write('Import operation failed.\n');
      logWriter.write(`${e}\n`);
    }
    else {
      console.log(`Import operation Failed:`);
      console.log(e);
    }
    if (conn !== undefined) {
      await conn.end();
    }
    if (pool !== undefined) {
      await pool.end();
    }
  }

  if (logWriter !== process.stdout) {
    logWriter.close();
  }

  if (parameters.SQLTRACE) {
    status.sqlTrace.close();
  }
}

main()