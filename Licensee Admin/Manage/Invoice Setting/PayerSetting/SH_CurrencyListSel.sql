/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[SH_CurrencyListSel]		
	 @currencyType				TINYINT	= 0 -- 0: Fiat, 1: Crypto, 99 --All
	 ,@IsExcludeTestingCurrency BIT		= 0
	 ,@OfferSite				VARCHAR(10)		= '0,1,2'
AS
/*
Created: 20250528@Danny
Task : Get all the currency list
DB: DBLIC.bodb_Licensee

Revisions:
    - 20250528@Danny: Get all the currency list [RedmineID: #226207]
	- 20250708@Danny: add param OfferSite [RedmineID: #231982]
	

Param's Explanation:
	EXEC SH_CurrencyListSel  @currencyType	 = 1
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @temp1 AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(65), CurrencyType TINYINT)
	INSERT INTO @temp1(currency, CurrencyName, CurrencyCode, CurrencyType)
	SELECT e.exchangeId, e.currency, e.Code, e.CurrencyType
	FROM  bodb02.dbo.Exchange e WITH (NOLOCK) 
	WHERE (
		@currencyType = 99 OR CurrencyType = @CurrencyType
	)
	AND 
	(
		( e.Currency NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)  AND @IsExcludeTestingCurrency = 1 )
	OR 
		@IsExcludeTestingCurrency  = 0
	)
	AND e.OfferSite IN (SELECT CAST(value AS TINYINT) FROM STRING_SPLIT(@OfferSite,','))

	BEGIN
		UPDATE t1
		SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')'
		FROM @temp1 t1
		INNER JOIN (
		   SELECT CurrencyCode
			FROM @temp1
			GROUP BY CurrencyCode
			HAVING COUNT(1) > 1
		) t2 ON t1.CurrencyCode = t2.CurrencyCode

		SELECT t.currency AS CurrencyID
			,CASE WHEN t.CurrencyType = 1 THEN t.CurrencyName
				ELSE CurrencyCode
				END AS CurrencyCode
			, t.CurrencyName
		FROM @temp1 t
		ORDER BY CurrencyCode

	END
END
GO