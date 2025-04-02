/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20250410@Danny
	DB: DBLIC-bodb_Licensee
	Task: Regen data AGC product
	ProductId = 37
*/
USE bodb_LicenseeReport
GO

-- Remove testing data
TRUNCATE TABLE SabaPlayPerformance


-- regen data Saba Promotion
EXEC dbo.GEN_rptBettingByProduct
	@date				= '2025-04-02',
	@date2				= '2025-04-06',
	@DataSource			= 'Rpt_Betting',
	@SeparatedProductID	= 37,
	@ProductCodes		= 'SPR',
	@IsManual			= 1