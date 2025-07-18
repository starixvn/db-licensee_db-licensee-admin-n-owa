/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_SelCurrencyByParty]		
	 @PartyID		INT				= 0
	, @excludeTest	BIT				= 0
	, @SystemMode	VARCHAR(10)		= 'LA'
	, @OfferSite    VARCHAR(10)		= '0,1,2'
AS
/*
Created: 20140828@Florent
Task : Get all the currency by a party
DB: DBCUST.bodb_Licensee

Revisions:
    - 20141218@Florent: add more currency from credit licensee   
	- 20150105@Florent: use f_SelLicenseeCust
	- 20150312@Florent: add systemmode to use on report settlement
	- 20200225@Parsons: Support-HID-currency [#128856]
	- 20201003@Danny: Support USDT as base currency [RedmineID: #177718]
	- 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20250708@Danny: add param OfferSite [RedmineID: #231982]

Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	DECLARE @temp AS TABLE (currency INT)

	BEGIN
		INSERT INTO @temp
		SELECT DISTINCT Currency
		FROM dbo.LA_f_SelLicenseeCust(0) AS lc
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID
		WHERE (
				@PartyID = 0
				OR p.PartyID = @PartyID
				)
			AND (
				@excludeTest = 0
				OR (
					@excludeTest = 1
					AND Currency NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
					)
				)
	END

	-- get all currency for credit
	IF (@PartyID = 0 
		 OR 1 = (SELECT TOP 1 1 
				FROM dbo.OAS_Party p WITH(NOLOCK) 
				    INNER JOIN OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID AND pd.IsDeposit = 0
				WHERE p.PartyID = @PartyID ) )
	BEGIN
	    INSERT INTO @temp
	    SELECT DISTINCT exchangeid
	    FROM CustDB.dbo.Exchange WITH (NOLOCK)
	    WHERE exchangeid NOT IN (SELECT Currency FROM @temp)
	END


	DECLARE @temp1 AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(65), CurrencyType TINYINT)
	INSERT INTO @temp1(currency, CurrencyName, CurrencyCode, CurrencyType)
	SELECT t.currency, e.currency, e.Code, e.CurrencyType
	FROM @temp t
	INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON t.currency = e.exchangeid
	WHERE e.OfferSite IN (SELECT CAST(value AS TINYINT) FROM STRING_SPLIT(@OfferSite,','))


	IF ( @PartyID <> 0 
		AND NOT EXISTS (SELECT TOP 1 1 
				FROM dbo.OAS_Party p WITH(NOLOCK) 
				    INNER JOIN OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID AND pd.IsDeposit = 0
				WHERE p.PartyID = @PartyID  )
		)
	BEGIN
		UPDATE t1
		SET	t1.CurrencyCode = CASE WHEN t1.currency IN (96, 202, 208, 206, 209) THEN t1.CurrencyCode + ' (' + t1.CurrencyName + ')'
									WHEN t1.currency = 142 THEN 'USDT'
								END
		FROM	@temp1 t1
		WHERE  t1.currency IN (96, 202, 208, 142, 206, 209)

		UPDATE t1
		SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')'
		FROM @temp1 t1
		INNER JOIN (
			SELECT CurrencyCode
			FROM @temp1
			GROUP BY CurrencyCode
			HAVING COUNT(1) > 1
		) t2 ON t1.CurrencyCode = t2.CurrencyCode

		SELECT t.currency
		,CASE 
			WHEN t.currency = 20 THEN 'UUS'
			WHEN t.currency = 51 THEN CASE  WHEN @SystemMode = 'LA' THEN 'INH'
											WHEN @SystemMode = 'INV' THEN 'VND'
											END
			WHEN t.currency = 92 THEN 'HID'
			WHEN t.currency = 142 THEN 'USDT'
			WHEN t.CurrencyType = 1 THEN t.CurrencyName
			ELSE CurrencyCode
			END AS CurrencyName
		FROM @temp1 t
		ORDER BY CurrencyName
	END
	ELSE
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

		SELECT t.currency
			,CASE 
				WHEN t.currency = 20 THEN 'UUS'
				WHEN t.currency = 51 THEN CASE  WHEN @SystemMode = 'LA' THEN 'INH'
												WHEN @SystemMode = 'INV' THEN 'VND'
												END
				WHEN t.currency = 92 THEN 'HID'
				WHEN t.currency = 142 THEN 'USDT'
				WHEN t.CurrencyType = 1 THEN t.CurrencyName
				ELSE CurrencyCode
				END AS CurrencyName
		FROM @temp1 t
		ORDER BY CurrencyName

	END
END
GO