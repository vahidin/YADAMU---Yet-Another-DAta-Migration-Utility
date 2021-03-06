"use strict"

const Yadamu = require('../../common/yadamu.js');
const oracledb = require('oracledb');

const sqlSetSavePoint = 
`SAVEPOINT BATCH_INSERT`;

const sqlRollbackSavePoint = 
`ROLLBACK TO BATCH_INSERT`;

class TableWriter {

  constructor(dbi,schema,tableName,tableInfo,status,logWriter) {
    this.dbi = dbi;
    this.schema = schema;
    this.tableName = tableName
    this.tableInfo = tableInfo;
    this.status = status;
    this.logWriter = logWriter;    

    this.batch = [];
    this.lobList = [];

    this.lobUsage = 0;
    this.batchCount = 0;
    this.batchLength = 0;

    this.startTime = new Date().getTime();
    this.endTime = undefined;
    this.insertMode = 'Batch';

    this.skipTable = false;

    this.logDDLIssues   = (this.status.loglevel && (this.status.loglevel > 2));
    this.logDDLIssues   = true;
  }

  async disableTriggers(schema,tableName) {
  
    const sqlStatement = `ALTER TABLE "${schema}"."${tableName}" DISABLE ALL TRIGGERS`;
    return this.dbi.executeSQL(sqlStatement,[]);
    
  }

  async initialize() {
    await this.disableTriggers(this.schema,this.tableName);
  }

  batchComplete() {
    return this.batch.length === this.tableInfo.batchSize;
  }
  
  commitWork(rowCount) {
    return (rowCount % this.tableInfo.commitSize) === 0;
  }
  
  async enableTriggers(schema,tableName) {
  
    const sqlStatement = `ALTER TABLE "${schema}"."${tableName}" ENABLE ALL TRIGGERS`;
    return this.dbi.executeSQL(sqlStatement,[]);
    
  }

  async appendRow(row) {
      
    row = await Promise.all(this.tableInfo.targetDataTypes.map(function(targetDataType,idx) {
      if (row[idx] !== null) {
        const dataType = Yadamu.decomposeDataType(targetDataType);
        if (dataType.type === 'JSON') {
          // JSON store as BLOB results in Error: ORA-40479: internal JSON serializer error during export operations
          // row[idx] = Buffer.from(JSON.stringify(row[idx]))
          // Default JSON Storage model is JSON store as CLOB.
          // JSON must be shipped in Serialized Form
          return JSON.stringify(row[idx])
        } 
        if (this.tableInfo.binds[idx].type === oracledb.CLOB) {
          this.lobUsage++
          // A promise...
          return this.dbi.trackClobFromString(row[idx], this.lobList)                                                                    
        }
        switch (dataType.type) {
          case "BLOB" :
            return Buffer.from(row[idx],'hex');
          case "RAW":
            return Buffer.from(row[idx],'hex');
          case "BOOLEAN":
            switch (row[idx]) {
              case true:
                 return 'true';
                 break;
              case false:
                 return 'false';
                 break;
              default:
                return row[idx]
            }
          case "DATE":
            if (row[idx] instanceof Date) {
              return row[idx].toISOString()
            }
          case "TIMESTAMP":
            // A Timestamp not explicitly marked as UTC should be coerced to UTC.
            // Avoid Javascript dates due to lost of precsion.
            // return new Date(Date.parse(row[idx].endsWith('Z') ? row[idx] : row[idx] + 'Z'));
            if (typeof row[idx] === 'string') {
              return (row[idx].endsWith('Z') || row[idx].endsWith('+00:00')) ? row[idx] : row[idx] + 'Z';
            }
            if (row[idx] instanceof Date) {
              return row[idx].toISOString()
            }
          case "XMLTYPE" :
            // Cannot passs XMLTYPE as BUFFER
            // Reason: ORA-06553: PLS-307: too many declarations of 'XMLTYPE' match this call
            // row[idx] = Buffer.from(row[idx]);
          default :
            return row[idx]
        }
      }
    },this))
    this.batch.push(row);
    return this.batch.length;
  }

  avoidMutatingTable(insertStatement) {

    let insertBlock = undefined;
    let selectBlock = undefined;
  
    let statementSeperator = "\nwith\n"
    if (insertStatement.indexOf(statementSeperator) === -1) {
      statementSeperator = "\nselect :1";
      if (insertStatement.indexOf(statementSeperator) === -1) {
         // INSERT INTO TABLE (...) VALUES ... 
        statementSeperator = "\n	     values (:1";
        insertBlock = insertStatement.substring(0,insertStatement.indexOf('('));
        selectBlock = `select ${insertStatement.slice(insertStatement.indexOf(':1'),-1)} from DUAL`;   
      }
      else {
         // INSERT INTO TABLE (...) SELECT ... FROM DUAL;
        insertBlock = insertStatement.substring(0,insertStatement.indexOf('('));
        selectBlock = insertStatement.substring(insertStatement.indexOf(statementSeperator)+1);   
      }
    }
    else {
      // INSERT /*+ WITH_PL/SQL */ INTO TABLE(...) WITH PL/SQL SELECT ... FROM DUAL;
      insertBlock = insertStatement.substring(0,insertStatement.indexOf('\\*+'));
      selectBlock = insertStatement.substring(insertStatement.indexOf(statementSeperator)+1);   
    }
       
    const plsqlBlock  = 
`declare
  cursor getRowContent 
  is
  ${selectBlock};
begin
  for x in getRowContent loop
    ${insertBlock}
           values x;
  end loop;
end;`
    return plsqlBlock;
  }
 
  freeLobList() {
    this.lobList.forEach(async function(lob,idx) {
      try {
        await lob.close();
      } catch(e) {
        this.logWriter.write(`LobList[${idx}]: Error ${e}\n`);
      }   
    },this)
  }
  
  hasPendingRows() {
    return this.batch.length > 0;
  }
      
  async writeBatch() {
      
    // Ideally we used should reuse tempLobs since this is much more efficient that setting them up, using them once and tearing them down.
    // Infortunately the current implimentation of the Node Driver does not support this, once the 'finish' event is emitted you cannot truncate the tempCLob and write new content to it.
    // So we have to free the current tempLob Cache and create a new one for each batch
    
    try {
      this.batchCount++;
      this.insertMode = 'Batch';
      await this.dbi.executeSQL(sqlSetSavePoint,[])
      const results = await this.dbi.executeMany(this.tableInfo.dml,this.batch,{bindDefs : this.tableInfo.binds});
      this.endTime = new Date().getTime();
      // console.log(`Batch:${this.batchCount}. ${this.batch.length} rows inserted`)
      this.batch.length = 0;
      this.freeLobList();
      return this.skipTable
    } catch (e) {
      await this.dbi.executeSQL(sqlRollbackSavePoint,[])
      if (e.errorNum && (e.errorNum === 4091)) {
        // Mutating Table - Convert to Cursor based PL/SQL Block
        status.warningRaised = true;
        this.logWriter.write(`${new Date().toISOString()}[INFO]: TableWriter.writeBatch("${this.tableName}",${this.batch.length}. executeMany() operation raised ${e}. Retrying using PL/SQL Block.\n`);
        this.tableInfo.dml = this.avoidMutatingTable(this.tableInfo.dml);
        if (this.status.sqlTrace) {
          this.status.sqlTrace.write(`${this.tableInfo.dml}\n/\n`);
        }
        try {
          const results = await this.dbi.executeMany(this.tableInfo.dml,this.batch,{bindDefs : this.tableInfo.binds}); 
          this.endTime = new Date().getTime();
          this.batch.length = 0;
          return this.skipTable
        } catch (e) {
          await this.connection.rollback();
          if (this.logDDLIssues) {
            this.logWriter.write(`${new Date().toISOString()}[INFO]: TableWriter.writeBatch("${this.tableName}",${this.batch.length}). executeMany() operation with PL/SQL block raised ${e}. Retrying using execute() loop.\n`);
            this.logWriter.write(`${this.tableInfo.dml}\n`);
            this.logWriter.write(`${this.tableInfo.targetDataTypes}\n`);
            this.logWriter.write(`${JSON.stringify(this.tableInfo.binds)}\n`);
            this.logWriter.write(`${JSON.stringify(this.batch[0])}\n`);
          }
        }
      } 
      else {  
        if (this.logDDLIssues) {
          this.logWriter.write(`${new Date().toISOString()}[INFO]: TableWriter.writeBatch("${this.tableName}",${this.batch.length}). executeMany() operation raised ${e}. Retrying using execute() loop.\n`);
          this.logWriter.write(`${this.tableInfo.dml}\n`);
          this.logWriter.write(`${this.tableInfo.targetDataTypes}\n`);
          this.logWriter.write(`${JSON.stringify(this.tableInfo.binds)}\n`);
          this.logWriter.write(`${JSON.stringify(this.batch[0])}\n`);
        }
      }
    }

    let row = undefined;
    this.insertMode = 'Iterative';
    for (row in this.batch) {
      try {
        let results = await this.dbi.executeSQL(this.tableInfo.dml,this.batch[row])
      } catch (e) {
        this.logWriter.write(`${new Date().toISOString()}[ERROR]: TableWriter.writeBatch("${this.tableName}",${row}). insert() operation raised ${e}.\n`);
        this.status.warningRaised = true;
        if (this.logDDLIssues) {
          this.logWriter.write(`${this.tableInfo.dml}\n`);
          this.logWriter.write(`${this.tableInfo.targetDataTypes}\n`);
          this.logWriter.write(`${JSON.stringify(this.batch[row])}\n`);
        } 
        // Write Record to 'bad' file.
        try {
          if ( this.status.importErrorMgr ) {
            this.status.importErrorMgr.logError(this.tableName,this.batch[row]);
          }
          else {
            this.logWriter.write(`${new Date().toISOString()} [ERROR]: Data [${this.batch[row]}].\n`)               
          }
        } catch (e) {
        //  Catch Max Errors Exceeded Assertion
          await this.connection.rollback();
          this.skipTable = true;
          this.logWriter.write(`${new Date().toISOString()}[ERROR]: TableWriter.writeBatch("${this.tableName}",${row}). Skipping table. Reason: ${e.message}.\n`);
        }
      }
    } 
    // console.log(`Iterative:${this.batchCount}. ${this.batch.length} rows inserted`)
    // Iterative must commit to allow a subsequent batch to rollback.
    this.endTime = new Date().getTime();
    this.batch.length = 0;
    this.freeLobList();
    return this.skipTable     
  }

  async finalize() {
    if (this.hasPendingRows()) {
      this.skipTable = await this.writeBatch();   
    }
    await this.dbi.commitTransaction();
    await this.enableTriggers(this.schema,this.tableName);
    return {
      startTime    : this.startTime
    , endTime      : this.endTime
    , insertMode   : this.insertMode
    , skipTable    : this.skipTable
    }    
  }

}

module.exports = TableWriter;