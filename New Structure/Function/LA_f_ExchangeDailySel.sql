USE [bodb02]
GO
/****** Object:  UserDefinedFunction [dbo].[LA_f_ExchangeDailySel]    Script Date: 20/03/2015 16:06:20 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_ExchangeDailySel] (
	@fromdate 			DATETIME
	, @todate 			DATETIME
	, @BaseCurrency 	VARCHAR(10)
)
	
/*  
	Created: 20150320@Patrick
	Task : Get exhange daily
	DB: DB052.bodb02
	Original: Lrf_f_GetExchangeDaily
	Revisions:  

	Param's Explanation:  			
*/
RETURNS @tempDate TABLE (exchangedate DATETIME, ExchangeId INT, Code VARCHAR(5)
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
			SELECT @tmpDate, ExchangeId, Code
				, CASE WHEN @BaseCurrency = 'MYR' THEN MYR
					WHEN @BaseCurrency = 'USD' THEN USD
					WHEN @BaseCurrency = 'EUR' THEN EUR
					WHEN @BaseCurrency = 'CNY' THEN CNY
					WHEN @BaseCurrency = 'GBP' THEN GBP
					ELSE 1 END BaseCurrencyRate
				--, MYR, USD, EUR, CNY, GBP, actualrate
			FROM dbo.ExchangeDailyOanda WITH (NOLOCK)
			WHERE ExchangeDate = @tmpToDate
	
			SET @tmpDate = DATEADD(dd,1,@tmpDate)
		END

		SET @i = @i + 1
		SET @tmpFromDate = DATEADD(m, 1, @tmpFromDate)
	END
RETURN 
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_f_ExchangeDailySel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_f_ExchangeDailySel] TO bodbAdminNet 