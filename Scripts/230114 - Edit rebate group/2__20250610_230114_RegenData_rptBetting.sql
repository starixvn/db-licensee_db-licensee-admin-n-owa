 /*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
USE [bodb_LicenseeReport]

GO

/*
	Create : 20250610@Danny
	Regen data for rptBetting [Redmine: #230114] 
	DB: DBLIC.bodb_LicenseeReport
*/
 
EXEC [Task_rptBetting_CheckData_Job]
	@FromDate  = '2025-06-05'
	, @ToDate  = '2025-06-05'
	, @Step  = 0
	, @AllowCorrect = 1
	 
GO