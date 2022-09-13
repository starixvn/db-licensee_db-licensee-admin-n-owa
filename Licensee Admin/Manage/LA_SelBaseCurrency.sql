/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,dwrs2" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_SelBaseCurrency]	
	@BaseCurrencyDefault	VARCHAR(10) = 'EUR'
AS
/*
	Created: 20150312@Florent
	Task : Get all BaseCurrency
	DB: DB052.bodb_licensee
	
	Revisions:
		- 20150703@Florent: add currency MYR
		- 20171220@Parsons: increase length for variables [#88197]
		- 20190408@Bruce: grant permission for dwrs2 [#105205]

*/
BEGIN
	SET NOCOUNT ON
	
	SELECT CurrencyId, CurrencyName
	FROM (
			SELECT e.exchangeid AS CurrencyId
				, CASE WHEN e.exchangeid = 142 THEN 'USDT' ELSE e.Code END AS CurrencyName
				, CASE e.Code WHEN @BaseCurrencyDefault THEN 1 ELSE 0 END AS [Default]
			FROM bodb02.dbo.Exchange e WITH (NOLOCK)
			WHERE e.Code IN 
							(
								  'CNY' -- ExchangeID = 13
								, 'EUR' -- ExchangeID = 6		
								, 'GBP' -- ExchangeID = 12
								, 'USD' -- ExchangeID = 3	
								, 'MYR'	-- ExchangeID = 2	
								, 'UST' -- ExchangeID = 142	
							)
								AND e.exchangeid IN
							(
								  2
								, 3
								, 6
								, 12
								, 13
								, 142
							)						
		) c
	ORDER BY [Default] DESC
END
GO