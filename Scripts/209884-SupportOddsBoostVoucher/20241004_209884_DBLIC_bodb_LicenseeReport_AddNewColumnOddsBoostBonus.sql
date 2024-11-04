/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20241004@Sally
	DB: DBLIC.bodb_licenseeReport
	Task: Support Odds Boost Voucher [#209884]
	- Add new column OddsBoostBonus table rptLicenseeReconciliation
*/
USE bodb_licenseeReport
GO

ALTER TABLE dbo.rptLicenseeReconciliation
ADD OddsBoostBonus MONEY  