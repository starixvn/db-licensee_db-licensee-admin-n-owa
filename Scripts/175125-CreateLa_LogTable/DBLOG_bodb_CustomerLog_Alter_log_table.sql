/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/

/*
	Created: 20230310@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Alter LA log setting table [#175125]
	Description: Remove some unused columns, Insert some data
*/
USE bodb_CustomerLog
-- Remove some unused columns
-- LA_LogAction
ALTER TABLE LA_LogAction DROP CONSTRAINT DF_LA_LogAction_IsInternal ;
ALTER TABLE LA_LogAction DROP COLUMN ActionNameCH, ActionNameCS, ActionNameJP, ActionNameIT, ActionNameTH, ActionNameKO,IsInternal ;
--Rename XsltContent to Items
EXEC sp_rename 'dbo.LA_LogAction.XsltContent', 'Items', 'COLUMN';

--LA_LogActionType
ALTER TABLE LA_LogActionType DROP COLUMN ActionTypeNameCH,ActionTypeNameCS, ActionTypeNameJP, ActionTypeNameIT, ActionTypeNameTH, ActionTypeNameKO ;

INSERT INTO LA_LogActionType (ActionTypeID, ActionTypeNameEN)
VALUES (10, 'Payer'), (11, 'Biller'), (12, 'Product Charge Rate'), (13, 'Minimun Fee'), (14, 'Waive'), (15, 'Group Min Fee'), (16, 'Discount Group'), (17, 'Rebate Group');
 
 -- LA_UserLog_RunSP
 ALTER TABLE LA_LogActionType DROP COLUMN Doing;
 ALTER TABLE LA_LogActionType ADD IP VARCHAR(45);
 CREATE INDEX IDX_LA_UserLog_RunSP  ON LA_UserLog_RunSP(LogDate, ActionID, CustID)