/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20231004@Danny
	DB: DBLIC.bodb_licenseeReport
	Task: SB - Parlay Boost integration [#191662]
	Description: Alter table add new column
*/
USE bodb_licenseeReport
GO

ALTER TABLE rptLicPerformanceAnalysis ADD HouseParlayBoostBonus MONEY