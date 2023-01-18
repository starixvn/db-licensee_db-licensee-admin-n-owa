/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20221221@Danny
	DB: DBLIC-bodb_LicenseeReport
	Task: LA - rptLicenseeReconciliation - Add new column: PlayerTips
*/
USE bodb_LicenseeReport
GO

ALTER TABLE dbo.rptLicenseeReconciliation
	ADD PlayerTips MONEY NULL
GO