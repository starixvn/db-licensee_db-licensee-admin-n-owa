/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/

/*
	Created: 20220929@Malcolm
	DB: DBLOG.bodb_CustomerLog
	Task: Update action name
*/
USE bodb_CustomerLog
GO

UPDATE LogAction WITH(ROWLOCK, UPDLOCK)
	SET 
		ActionNameEN = 'Insert/Update/Delete charge rate by currency'
		,ActionNameCH = 'Insert/Update/Delete charge rate by currency'
		,ActionNameCS = 'Insert/Update/Delete charge rate by currency'
		,ActionNameJP = 'Insert/Update/Delete charge rate by currency'
		,ActionNameIT = 'Insert/Update/Delete charge rate by currency'
		,ActionNameTH = 'Insert/Update/Delete charge rate by currency'
		,ActionNameKO = 'Insert/Update/Delete charge rate by currency'
		,ActionNameVI = 'Insert/Update/Delete charge rate by currency'
		,ActionNameCN = 'Insert/Update/Delete charge rate by currency'
WHERE ActionID = 5568