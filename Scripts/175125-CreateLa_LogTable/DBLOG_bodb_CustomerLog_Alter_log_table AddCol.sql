/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/

/*
	Created: 20230310@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Alter LA log setting table [#175125]
	Description: Remove some unused columns, Insert some data
*/
USE bodb_CustomerLog

 ALTER TABLE LA_UserLog_RunSP Add  Doing NVARCHAR(MAX);
