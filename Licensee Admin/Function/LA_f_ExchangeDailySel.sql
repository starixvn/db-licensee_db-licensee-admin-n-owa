/*<info serverAlias="DBEXT-bodb02,DBCUST-CustDB" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION [dbo].[LA_f_ExchangeDailySel] (
	@fromdate DATETIME
	, @todate DATETIME
	, @BaseCurrency VARCHAR(10)
)
	
/*  
	Created: 20150320@Patrick
	Task: Get exhange daily
	DB: DBEXT.bodb02, DBCUST.CustDB
	
	Revisions:  
		- 20160413@Francis: Support THB Base Currency
		- 20160920@Harper : Support HKD Base Currency
		- 20170712@Harper: Support IDR Base Currency [RedmineID: #79309]
		- 20180301@Harper: Support SGD as base currency [RedmineID: #91339] 
		- 20221003@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20221209@Danny: Show USD (USDT) instead of USD only [RedmineID: #180313]
		- 20220216@Danny: Incorporate USDTJP currency [RedmineID: #183461]

	Param's Explanation:				
*/
RETURNS @tempDate TABLE (exchangedate DATETIME, ExchangeId INT, Code VARCHAR(10)
		, BaseCurrencyRate FLOAT
		--, MYR FLOAT, USD FLOAT, EUR FLOAT, CNY FLOAT, GBP FLOAT, actualrate FLOAT
		, UNIQUE CLUSTERED(exchangedate, exchangeid))
AS 
BEGIN
	DECLARE @tmpFromDate DATETIME, @tmpToDate DATETIME, @maxExchangeDate DATETIME
		, @tmpDate DATETIME, @gapDate DATETIME, @i INT

	SELECT @maxExchangeDate = MAX(exchangedate) 
	FROM dbo.ExchangeDailyOanda (NOLOCK)

	SELECT @tmpFromDate = @fromdate, @i = 0
	WHILE (DATEDIFF (m, @tmpFromDate, @todate) >= 0)
	BEGIN
		IF @i = 1
		BEGIN
			SET @tmpFromDate = CAST(CONVERT(VARCHAR(10), DATEADD(dd, -(DAY(@tmpFromDate) -1), @tmpFromDate), 111) AS DATETIME)
		END

		SET @tmpToDate = CAST(CONVERT(VARCHAR(10), DATEADD(s, -1, DATEADD(mm, DATEDIFF(m, 0, @tmpFromDate) +1, 0)), 111) AS DATETIME)

		IF @tmpToDate > @maxExchangeDate
		BEGIN
			SET @tmpToDate = @maxExchangeDate
		END

		SET @tmpDate = @tmpFromDate
		WHILE (@tmpDate <= @tmpToDate AND @tmpDate <= @todate)
		BEGIN
			INSERT INTO @tempDate (exchangedate, ExchangeId, Code, BaseCurrencyRate)--, MYR, USD, EUR, CNY, GBP, actualrate)
			SELECT @tmpDate, t.ExchangeId
				,CASE WHEN t.ExchangeId = 142 THEN 'USDT'
					WHEN t.ExchangeId = 96 THEN 'USD (USDT)'
					ELSE t.Code END 
				,CASE WHEN @BaseCurrency = 'MYR' THEN t.MYR
					WHEN @BaseCurrency = 'USD' THEN t.USD
					WHEN @BaseCurrency = 'EUR' THEN t.EUR
					WHEN @BaseCurrency = 'CNY' THEN t.CNY
					WHEN @BaseCurrency = 'GBP' THEN t.GBP
					WHEN @BaseCurrency = 'THB' THEN t.THB
					WHEN @BaseCurrency = 'HKD' THEN t.HKD
					WHEN @BaseCurrency = 'IDR' THEN t.IDR
					WHEN @BaseCurrency = 'SGD' THEN t.SGD 
					WHEN @BaseCurrency = 'USDT' THEN u.USDT  
					ELSE 1 END BaseCurrencyRate
				--, MYR, USD, EUR, CNY, GBP, actualrate
			FROM dbo.ExchangeDailyOanda t WITH (NOLOCK)
			LEFT JOIN dbo.ExchangeDaily_Crypto u WITH(NOLOCK) ON t.ExchangeDate = u.ExchangeDate AND t.ExchangeId = u.ExchangeId
			WHERE t.ExchangeDate = @tmpToDate
	
			SET @tmpDate = DATEADD(dd,1,@tmpDate)
		END

		SET @i = @i + 1
		SET @tmpFromDate = DATEADD(m, 1, @tmpFromDate)
	END
RETURN 
END
GO