/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20241009@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: regen AGC data
*/



DECLARE @fDate SMALLDATETIME = '2024-09-10'
DECLARE @tDate SMALLDATETIME = '2024-09-10'

-- regen table rpt_BettingByProduct
EXEC dbo.GEN_rptBettingByProduct @date = @fDate
								, @date2 = @tDate
								, @DataSource = 'SeparatedProduct'
								, @SeparatedProductID = 10
								, @ProductCodes = 'AGC'
								, @IsManual = 1





