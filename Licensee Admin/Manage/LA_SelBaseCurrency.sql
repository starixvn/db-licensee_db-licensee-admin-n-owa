USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_SelBaseCurrency]	
	@BaseCurrencyDefault	VARCHAR(3) = 'EUR'
AS
/*
	Created: 20150312@Florent
	Task : Get all BaseCurrency
	DB: DB052.bodb_licensee
	Revison:
		- 20150703@Florent: add currency MYR

	Revisions:
	Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	
	SELECT CurrencyId, CurrencyName
	FROM (
			SELECT e.exchangeid AS CurrencyId
				, e.Code AS CurrencyName
				, CASE e.Code WHEN @BaseCurrencyDefault THEN 1 ELSE 0 END AS [Default]
			FROM bodb02.dbo.Exchange e WITH (NOLOCK)
			WHERE e.Code IN 
							(
								  'CNY' -- ExchangeID = 13
								, 'EUR' -- ExchangeID = 6		
								, 'GBP' -- ExchangeID = 12
								, 'USD' -- ExchangeID = 3	
								, 'MYR'	-- ExchangeID = 2	
							)
								AND e.exchangeid IN
							(
								  2
								, 3
								, 6
								, 12
								, 13
							)						
		) c
	ORDER BY [Default] DESC
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_SelBaseCurrency] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_SelBaseCurrency] TO bodbAdminNet