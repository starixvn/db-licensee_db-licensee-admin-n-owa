/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250604@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: regen Exchange data
*/



DECLARE @fDate SMALLDATETIME = '2025-05-01'
DECLARE @tDate SMALLDATETIME = '2025-05-31'

-- regen table rpt_BettingByProduct
EXEC dbo.GEN_rptBettingByProduct @date = @fDate
								, @date2 = @tDate
								, @DataSource = 'SeparatedProduct'
								, @SeparatedProductID = 31
								, @ProductCodes = 'BX'
								, @IsManual = 1





