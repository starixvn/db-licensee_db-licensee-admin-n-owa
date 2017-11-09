/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/

ALTER FUNCTION [dbo].[LA_f_SubExchangeDailySel] (
	@FromDate					SMALLDATETIME
	, @ToDate					SMALLDATETIME
	, @BaseCurrency				VARCHAR(10)
)	
/*  
	Created: 20171107@Don
	Task : Get sub exchange daily
	DB: DB052.bodb02
	Revisions:  

	Param's Explanation:  			
	- 20171107@Don: Initial version

*/
RETURNS @tempDate TABLE 
	(
		FirstExchangeDateByMonth			SMALLDATETIME
		, LastExchangeDateByMonth			SMALLDATETIME
		, ExchangeId						INT
		, Code								VARCHAR(5)
		, BaseCurrencyRate					FLOAT
	)
AS 
BEGIN
	DECLARE @tblDate AS TABLE(number INT PRIMARY KEY, firstday SMALLDATETIME, lastday SMALLDATETIME)

	DECLARE @MaxExchangeDate SMALLDATETIME
	DECLARE @MonthDist INT

	SELECT @MaxExchangeDate = MAX(ExchangeDate) 
	FROM dbo.ExchangeDailyOanda WITH(NOLOCK)

	SET @MonthDist = DATEDIFF(MONTH, @FromDate, @ToDate)

	WHILE (@MonthDist >= 0)
	BEGIN
		INSERT INTO @tblDate(number)
			VALUES(@MonthDist)

		SET @MonthDist = @MonthDist - 1
	END

	UPDATE @tblDate 
	SET
		firstday = CONVERT(VARCHAR(25), DATEADD(dd, -(DAY(DATEADD(MONTH, number, @FromDate))-1), DATEADD(MONTH, number, @FromDate)), 101),
		lastday = CONVERT(VARCHAR(25), DATEADD(dd, -(DAY(DATEADD(MONTH, 1, DATEADD(MONTH, number, @FromDate)))), DATEADD(MONTH, 1, DATEADD(MONTH, number, @FromDate))), 101)

	;WITH cte AS (
		SELECT TOP 1 number FROM @tblDate ORDER BY number ASC
		UNION ALL
		SELECT TOP 1 number FROM @tblDate ORDER BY number DESC
	)
	UPDATE dt
	SET
		firstday = CASE WHEN firstday < @FromDate THEN @FromDate ELSE firstday END,
		lastday = CASE WHEN lastday > @ToDate THEN @ToDate ELSE lastday END
	FROM @tblDate dt 
		INNER JOIN cte ON dt.number = cte.number
	
	INSERT INTO @tempDate(FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeId, Code, BaseCurrencyRate)
		SELECT dt.firstday, dt.lastday, ex.ExchangeId, ex.Code, 
			CASE 
				WHEN @BaseCurrency = 'MYR' THEN MYR
				WHEN @BaseCurrency = 'USD' THEN USD
				WHEN @BaseCurrency = 'EUR' THEN EUR
				WHEN @BaseCurrency = 'CNY' THEN CNY
				WHEN @BaseCurrency = 'GBP' THEN GBP
				WHEN @BaseCurrency = 'THB' THEN THB
				WHEN @BaseCurrency = 'HKD' THEN HKD
				WHEN @BaseCurrency = 'IDR' THEN IDR
				ELSE 1 
			END BaseCurrencyRate
		FROM dbo.ExchangeDailyOanda ex WITH(NOLOCK)
			INNER JOIN @tblDate dt ON ex.ExchangeDate = dt.lastday

	RETURN 
END
GO