/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20231114@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Add new log setting RedmineId #194868
*/
USE [bodb_CustomerLog]
GO

INSERT INTO LA_LogAction (ActionID,	ActionTypeID,	SPName,	ActionNameEN,Items )

SELECT 1302 ActionID,	 ActionTypeID,	SPName,	 'Remove Minimun fee setting' ActionNameEN,  Items 
FROM LA_LogAction WITH(NOLOCK) WHERE  ActionID = 1300

UNION ALL

SELECT 1402 ActionID,	ActionTypeID,	SPName,	 'Remove Waive setting' ActionNameEN,  Items 
FROM LA_LogAction WITH(NOLOCK) WHERE  ActionID = 1400


