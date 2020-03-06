/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_SelCurrencyByParty]		
	 @PartyID		INT				= 0
	, @excludeTest	BIT				= 0
	, @SystemMode	VARCHAR(10)		= 'LA'
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
					AND Currency <> 20
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
	DECLARE @temp1 AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))
	INSERT INTO @temp1(currency, CurrencyName, CurrencyCode)
	SELECT t.currency, e.currency, e.Code
	FROM @temp t
	INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON t.currency = e.exchangeid

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
		,CASE t.currency
			WHEN 20
				THEN 'UUS'
			WHEN 51 
				THEN CASE WHEN @SystemMode = 'LA' THEN 'INH'
						  WHEN @SystemMode = 'INV' THEN 'VND'
					 END
			WHEN 92
				THEN 'HID'
			ELSE CurrencyCode
			END AS CurrencyName
	FROM @temp1 t
	ORDER BY CurrencyName
END
GO