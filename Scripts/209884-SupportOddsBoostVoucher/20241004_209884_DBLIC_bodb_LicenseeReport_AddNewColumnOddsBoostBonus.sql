/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20241004@Sally
	DB: DBLIC.bodb_licenseeReport
	Task: Support Odds Boost Voucher [#191662]
	- Add new column OddsBoostBonus table rptLicPerformanceAnalysis
*/
USE bodb_licenseeReport
GO

ALTER TABLE dbo.rptLicPerformanceAnalysis
ADD OddsBoostBonus MONEY  