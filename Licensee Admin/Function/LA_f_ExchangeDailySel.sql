/*<info serverAlias="DBEXT-bodb02,DBCUST-CustDB" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
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
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
		- 20230713@Danny: Incorporate USDT2 currency [RedmineID: #191165]
		- 20230823@Danny: Incorporate US$KH currency [RedmineID: #192544]
		- 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
		- 20250513@Danny: Modify logic to get the latest exchange date [RedmineID: #226741]

	Param's Explanation:				
*/
RETURNS @tempDate TABLE (exchangedate DATETIME, ExchangeId INT, Code VARCHAR(65)
		, BaseCurrencyRate FLOAT
		--, MYR FLOAT, USD FLOAT, EUR FLOAT, CNY FLOAT, GBP FLOAT, actualrate FLOAT
		, UNIQUE CLUSTERED(exchangedate, exchangeid))
AS 
BEGIN
	DECLARE @tmpFromDate DATETIME, @tmpToDate DATETIME, @maxExchangeDate DATETIME
		, @tmpDate DATETIME, @gapDate DATETIME, @i INT, @ReferencedExchangeDate DATETIME

	SELECT @maxExchangeDate = MAX(exchangedate) 
	FROM dbo.ExchangeDailyOanda (NOLOCK)

	SELECT @ReferencedExchangeDate = (
	SELECT a.ExchangeDate FROM (
		SELECT TOP 1 ExchangeDate, COUNT (1) AS ExchangeCount
		FROM ExchangeDailyOanda WITH (NOLOCK)
		WHERE ExchangeDate BETWEEN CAST( DATEFROMPARTS(YEAR(@maxExchangeDate), MONTH(@maxExchangeDate), 1)  AS SMALLDATETIME) AND CAST(@maxExchangeDate AS SMALLDATETIME)
		GROUP BY ExchangeDate
		ORDER BY 2 DESC, 1 DESC
		) a 
	)

	SELECT @tmpFromDate = @fromdate, @i = 0
	WHILE (DATEDIFF (m, @tmpFromDate, @todate) >= 0)
	BEGIN
		IF @i = 1
		BEGIN
			SET @tmpFromDate = CAST(DATEFROMPARTS(YEAR(@tmpFromDate), MONTH(@tmpFromDate), 1) AS DATETIME)
		END

		SET @tmpToDate = CAST(EOMONTH(@tmpFromDate) AS DATETIME)

		IF @tmpToDate > @ReferencedExchangeDate
		BEGIN
			SET @tmpToDate = @ReferencedExchangeDate
		END

		SET @tmpDate = @tmpFromDate
		WHILE (@tmpDate <= @todate)
		BEGIN
			INSERT INTO @tempDate (exchangedate, ExchangeId, Code, BaseCurrencyRate)--, MYR, USD, EUR, CNY, GBP, actualrate)
			SELECT @tmpDate, t.ExchangeId
				,CASE WHEN t.ExchangeId = 142 THEN 'USDT'
					WHEN t.ExchangeId IN (96,206) THEN 'USD (USDT)'
					WHEN t.ExchangeId = 202 THEN 'USD (USDTJP)'
					WHEN t.ExchangeId = 208 THEN 'USD (US$KH)'
					WHEN t.ExchangeId = 209 THEN 'MP'
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