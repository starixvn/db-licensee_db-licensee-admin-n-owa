/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ExchangeRateBillingSel]
	@CurrencyIds			VARCHAR(4000)	= ''
	, @ExchangeDate			DATETIME
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'

AS
/*
	Created: 20150318@Florent
	Task: Report - Licensee Settlement Report
	DB: DBLIC.bodb_licensee
	
	Revisions:
		- 20171219@Bruce: increase length for variables [#88197]
	
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