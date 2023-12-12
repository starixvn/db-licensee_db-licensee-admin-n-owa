/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231121@Danny
	DB: DBLIC-bodb_Licensee
	Task: Insert Data 3rd products [#191813]
	-- Run DB053, DB052 only
*/
USE bodb_Licensee
GO

SET NOCOUNT ON 

-- Remove data of closed products
/*
25	Cash Out  2022-01-31 (EndOfSupportDate)
15  Colossus Bets 2022-04-30 (EndOfSupportDate)
*/


delete from bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT with(rowlock)
where productID in (15, 25)

GO


