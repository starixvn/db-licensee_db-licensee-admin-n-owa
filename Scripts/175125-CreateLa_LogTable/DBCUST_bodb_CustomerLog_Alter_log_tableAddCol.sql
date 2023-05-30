/*<info serverAlias="DBCUST-bodb_CustomerLog"></info>*/

/*
	Created: 20230310@Danny
	DB: DBCUST.bodb_CustomerLog
	Task: Alter LA log setting table [#175125]
	Description: Remove some unused columns, Insert some data
*/
USE bodb_CustomerLog
 -- LA_UserLog_RunSP
 ALTER TABLE LA_UserLog_RunSP Add  Doing NVARCHAR(MAX);
