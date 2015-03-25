USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_ExchangeRateBillingSel]
	@CurrencyIds			VARCHAR(500)	= ''
	, @ExchangeDate			DATETIME
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

AS
/*  Created: 20150318@Florent		
	Task : Report - Licensee Settlement Report
	DB: DB052.bodb02
	Revisions:  
	Param's Explanation:  	
		+ @CurrencyIds: currency id list
		+ @ExchangeDate:
	Example:  exec [dbo].[LA_ExchangeRateBillingSel]
						@CurrencyIds		= '1,2,3,4'
						, @ExchangeDate		= '2015-01-01'
						, @BaseCurrencyName	= 'GBP'
*/  
SET NOCOUNT ON

BEGIN
	CREATE TABLE #tmpCurrency (CurrencyID INT PRIMARY KEY)

	INSERT INTO #tmpCurrency(CurrencyID)
	SELECT val
	FROM strSPlit(@CurrencyIds, ',')
	
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, BaseCurrencyRate AS Rate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@ExchangeDate, @ExchangeDate, @BaseCurrencyName)
	WHERE ExchangeId IN (SELECT DISTINCT CurrencyID FROM #tmpCurrency)	
	
	DROP TABLE #tmpCurrency
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_ExchangeRateBillingSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_ExchangeRateBillingSel] TO bodbAdminNet