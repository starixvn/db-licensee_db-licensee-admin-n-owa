/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[LA_BaseCurrency_Sel]	
	@BaseCurrencyDefault VARCHAR(10) = 'EUR'
AS
/*
	Created: 20190510@Percy
	Task : Get all BaseCurrency
	DB: DBCUST.CustDB
	Remark: Clone from SP: LA_SelBaseCurrency on DBLIC.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]

*/
BEGIN
	SET NOCOUNT ON
	
	SELECT CurrencyId, CurrencyName
	FROM (
			SELECT e.exchangeid AS CurrencyId
				, e.Code AS CurrencyName
				, CASE e.Code WHEN @BaseCurrencyDefault THEN 1 ELSE 0 END AS [Default]
			FROM dbo.Exchange e WITH (NOLOCK)
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