/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerCurrencySel]
	@PayerId		INT = 0
AS
/*
	Created: 20191121@Parsons
	Task : Set terms by currency
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20191121@Parsons: Set terms by currency [#FeatureID 120005]
		- 20200302@Parsons: Support-HID-currency [#128856]
		- 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20221209@Danny: Show USD (USDT) instead of USD only [RedmineID: #180313]

	Params:
	Example: EXEC [LA_PayerCurrencySel] 15
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @LicenseeID INT = (SELECT TOP 1 p.OldRefID FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @PayerId)
	DECLARE @Result TABLE (CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	
	INSERT INTO @Result(CurrencyId, CurrencyCode, CurrencyName)
	SELECT DISTINCT lc.Currency,
								CASE WHEN lc.Currency = 92 THEN 'HID'
									 WHEN lc.Currency = 142 THEN 'USDT'
									ELSE e.Code END AS Code, 
								CASE WHEN lc.Currency = 51 THEN 'VND' ELSE e.currency END AS CurrencyName
	FROM dbo.f_SelLicenseeCust(@LicenseeID) AS lc
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
	WHERE lc.Currency <> 20 -- exclude test
	
	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM @Result c1
	INNER JOIN (
		SELECT CurrencyCode
	    FROM @Result
	    GROUP BY CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.CurrencyCode = c2.CurrencyCode

	--- Update USDT
	UPDATE e
	SET e.CurrencyCode = e.CurrencyCode + ' (' + e.CurrencyName + ')' 
	FROM @Result e
	WHERE e.CurrencyName = 'USDT' AND e.CurrencyCode = 'USD'

	SELECT CurrencyId, CurrencyCode, CurrencyName
	FROM @Result
END
GO