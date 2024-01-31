/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20240319@Danny
	DB: DBLIC-bodb_Licensee
	Task: Regen data AGC product
	ProductId = 10
*/
USE bodb_LicenseeReport
GO

EXEC dbo.GEN_rptBettingByProduct
	@date				= '2024-03-01',
	@date2				= '2024-03-18',
	@DataSource			= 'SeparatedProduct',
	@SeparatedProductID	= 10,
	@ProductCodes		= 'AGC',
	@IsManual			= 1