CREATE OR ALTER FUNCTION MAP_FOREIGN_DATATYPES(@DATA_TYPE VARCHAR(128), @SIZE_CONSTRAINT VARCHAR(128)) 
RETURNS VARCHAR(128) 
AS
BEGIN
  RETURN CASE
	when @DATA_TYPE = 'VARCHAR' 
	  then 'VARCHAR(' + @SIZE_CONSTRAINT + ')'
	when @DATA_TYPE = 'VARCHAR2' 
	  then 'VARCHAR(' + @SIZE_CONSTRAINT + ')'
	when @DATA_TYPE = 'NUMBER'
      then 'DECIMAL(' + @SIZE_CONSTRAINT + ')'
	when @DATA_TYPE = 'DECIMAL'
      then 'DECIMAL(' + @SIZE_CONSTRAINT + ')'
	else
	 @DATA_TYPE
 /*  
  DECLARE  @V_DATA_TYPE  VARCHAR(128);

  SET @V_DATA_TYPE := @DATA_TYPE;

  case @V_DATA_TYPE
	when 'RAW'
      then return 'VARCHAR(',@SIZE_CONSTRAINT,')');
	when 'NVARCHAR2'
	  then return 'VARCHAR(',@SIZE_CONSTRAINT,')');
	when 'CLOB'
      then return 'NVARCHAR(MAX)';
	when 'NCLOB'
      then return 'NVARCHAR(MAX)';
	when 'BFILE'
      then return 'VARCHAR(256)';
	when 'ROWID'
      then return 'VARCHAR(32)';
	else
   	  if (instr(V_DATA_TYPE,'TIME ZONE') > 0) then
	    return 'TIMESTAMP';	
      end if;
	  if (INSTR(V_DATA_TYPE,'"."') > 0) then 
	    return 'NVARCHAR(MAX)';
	  end if;
   	  if ((instr(V_DATA_TYPE,'INTERVAL') = 1)) then
	    return 'VARCHAR(16)';
      end if;
	  return @V_DATA_TYPE;
*/
  END;
END;
GO
--
CREATE OR ALTER FUNCTION GENERATE_TABLE_COLUMNS(@COLUMN_LIST NVARCHAR(MAX),@DATA_TYPE_LIST NVARCHAR(MAX),@DATA_SIZE_LIST NVARCHAR(MAX)) 
RETURNS NVARCHAR(MAX) 
AS
BEGIN
  DECLARE @V_METADATA_TABLE    TABLE("COLUMN" VARCHAR(128),"DATATYPE" VARCHAR(128),"SIZE_CONSTRAINT" VARCHAR(128));
  DECLARE @RESULT NVARCHAR(MAX);

  SELECT @RESULT  = STRING_AGG('"' + c."VALUE" + '" ' + dbo.MAP_FOREIGN_DATATYPES(t."VALUE",s."VALUE"),',')
    FROM OPENJSON('[' + REPLACE(@COLUMN_LIST,'"."','\\".\\"') + ']') c,
	     OPENJSON('[' + REPLACE(@DATA_TYPE_LIST,'"."','\\".\\"') + ']') t,
		 OPENJSON('[' + REPLACE(@DATA_SIZE_LIST,'"."','\\".\\"') + ']') s
   WHERE c."KEY" = t."KEY" and c."KEY" = s."KEY";

   RETURN @RESULT;
END;
GO
--
CREATE OR ALTER FUNCTION GENERATE_WITH_CLAUSE(@COLUMN_LIST NVARCHAR(MAX),@DATA_TYPE_LIST NVARCHAR(MAX),@DATA_SIZE_LIST NVARCHAR(MAX)) 
RETURNS NVARCHAR(MAX) 
AS
BEGIN
  DECLARE @V_METADATA_TABLE    TABLE("COLUMN" VARCHAR(128),"DATATYPE" VARCHAR(128),"SIZE_CONSTRAINT" VARCHAR(128));
  DECLARE @RESULT NVARCHAR(MAX);

  SELECT @RESULT  = STRING_AGG('"' + c."VALUE" + '" ' + dbo.MAP_FOREIGN_DATATYPES(t."VALUE",s."VALUE") + ' ''$[' + CAST((c."KEY") as VARCHAR) + ']''',',')
    FROM OPENJSON('[' + REPLACE(@COLUMN_LIST,'"."','\\".\\"') + ']') c,
	     OPENJSON('[' + REPLACE(@DATA_TYPE_LIST,'"."','\\".\\"') + ']') t,
		 OPENJSON('[' + REPLACE(@DATA_SIZE_LIST,'"."','\\".\\"') + ']') s
   WHERE c."KEY" = t."KEY" and c."KEY" = s."KEY";

   RETURN @RESULT;
END;
GO
--
CREATE OR ALTER PROCEDURE IMPORT_JSON(@TARGET_DATABASE VARCHAR(128)) 
AS
BEGIN
  DECLARE @V_RESULTS       TABLE(
                             "TABLE_NAME"    VARCHAR(128)
							,"ROW_COUNT"     BIGINT
							,"ELAPSED_TIME"  BIGINT
							,"DDL_STATEMENT" NVARCHAR(MAX)
							,"DML_STATEMENT" NVARCHAR(MAX)
						   );
							   
  DECLARE @V_OWNER         VARCHAR(128);
  DECLARE @V_TABLE_NAME    VARCHAR(128);
  DECLARE @V_DDL_STATEMENT NVARCHAR(MAX);
  DECLARE @V_DML_STATEMENT NVARCHAR(MAX);
  
  DECLARE @V_RESULT        NVARCHAR(MAX) = '';

  DECLARE @V_START_TIME    DATETIME2;
  DECLARE @V_END_TIME      DATETIME2;
  DECLARE @V_ELAPSED_TIME  BIGINT;  
  DECLARE @V_ROW_COUNT     BIGINT;
  
  DECLARE GENERATE_STATEMENTS 
  CURSOR FOR 
  select OWNER
        ,TABLE_NAME
        ,'if object_id(''"' + @TARGET_DATABASE + '"."' + TABLE_NAME + '"'',''U'') is NULL begin create table "' + @TARGET_DATABASE + '"."' + TABLE_NAME + '" (' + dbo.GENERATE_TABLE_COLUMNS(SELECT_LIST,DATA_TYPE_LIST,SIZE_CONSTRAINTS) + ') END' "DDL_STATEMENT"
        ,'insert into "'  + @TARGET_DATABASE + '"."' + TABLE_NAME + '" (' + SELECT_LIST + ') select ' + SELECT_LIST + '  from "JSON_STAGING" CROSS APPLY OPENJSON("DATA",''$.data."' + TABLE_NAME + '"'') WITH ( ' + dbo.GENERATE_WITH_CLAUSE(SELECT_LIST,DATA_TYPE_LIST,SIZE_CONSTRAINTS) + ') data' "DML_STATEMENT"
   from "JSON_STAGING"
	     CROSS APPLY OPENJSON("DATA", '$.metadata') x
		 CROSS APPLY OPENJSON(x.VALUE) 
		             WITH(
					   OWNER                        VARCHAR(128)  '$.owner'
			          ,TABLE_NAME                   VARCHAR(128)  '$.tableName'
			          ,SELECT_LIST                  VARCHAR(MAX)  '$.columns'
			          ,DATA_TYPE_LIST               VARCHAR(MAX)  '$.dataTypes'
			          ,SIZE_CONSTRAINTS             VARCHAR(MAX)  '$.dataTypeSizing'
			          ,INSERT_SELECT_LIST           VARCHAR(MAX)  '$.insertSelectList'
                      ,COLUMN_PATTERNS              VARCHAR(MAX)  '$.columnPatterns');
 

  SET QUOTED_IDENTIFIER ON; 
					
  OPEN GENERATE_STATEMENTS;
  FETCH GENERATE_STATEMENTS INTO @V_OWNER, @V_TABLE_NAME, @V_DDL_STATEMENT, @V_DML_STATEMENT;
  WHILE @@FETCH_STATUS = 0 BEGIN
      EXEC(@V_DDL_STATEMENT)
	  SET @V_START_TIME = SYSUTCDATETIME();
 	  EXEC(@V_DML_STATEMENT)
	  SET @V_ROW_COUNT = @@ROWCOUNT;
	  SET @V_END_TIME = SYSUTCDATETIME();
	  SET @V_ELAPSED_TIME = DATEDIFF(MILLISECOND,@V_START_TIME,@V_END_TIME);
	  INSERT INTO @V_RESULTS values (@V_TABLE_NAME, @V_ROW_COUNT, @V_ELAPSED_TIME, @V_DDL_STATEMENT, @V_DML_STATEMENT);
      FETCH GENERATE_STATEMENTS INTO @V_OWNER, @V_TABLE_NAME, @V_DDL_STATEMENT, @V_DML_STATEMENT;
  END;
 
  CLOSE GENERATE_STATEMENTS;
  DEALLOCATE GENERATE_STATEMENTS;
  select "TABLE_NAME" as [tableName], "ROW_COUNT" as [rowCount], "ELAPSED_TIME" as [elapsedTime], "DDL_STATEMENT" as [ddlStatement], "DML_STATEMENT" as [dmlStatement] 
    from @V_RESULTS 
	 for JSON PATH;
end;
--
go
GO
--
exit