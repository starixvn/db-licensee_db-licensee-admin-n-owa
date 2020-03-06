/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountGroupCurrencySel]
	@DiscountGroupId	INT,
	@PartyId			INT
AS
/*  
	 Created: 20181022@Parsons [#99694]
	 Task : Configure discount settings by currency
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20181022@Parsons: Configure discount settings by currency [#99694]
		- 20200225@Parsons: Support-HID-currency [#128856]

	 Params:

	 Explannation: EXEC LA_DiscountGroupCurrencySel @DiscountGroupId = 0, @PartyId = 0
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CurrenciesOfLicensee TABLE (PartyId INT, CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	
	INSERT INTO @CurrenciesOfLicensee(PartyId, CurrencyId, CurrencyCode, CurrencyName)
	SELECT DISTINCT p.PartyId, lc.Currency, 
					CASE WHEN lc.Currency = 92 THEN 'HID' ELSE e.Code END AS Code, 
					CASE WHEN lc.Currency = 51 THEN 'VND' ELSE e.currency END AS CurrencyName
	FROM dbo.LA_f_SelLicenseeCust(0) AS lc
	INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID 
	INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
	WHERE lc.Currency <> 20 -- exclude test
			AND p.PartyID = @PartyId
	
	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM @CurrenciesOfLicensee c1
	INNER JOIN (
		SELECT PartyId, CurrencyCode
	    FROM @CurrenciesOfLicensee
	    GROUP BY PartyId, CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.PartyId = c2.PartyId AND c1.CurrencyCode = c2.CurrencyCode

	SELECT c.PartyId, c.CurrencyId, c.CurrencyCode AS CurrencyName, CASE WHEN d.CurrencyId IS NOT NULL THEN 1 ELSE 0 END IsSelected
	FROM @CurrenciesOfLicensee c
	LEFT JOIN LA_DiscountGroupCurrency d WITH(NOLOCK) ON
		d.PartyID = c.PartyId AND 
		d.DiscountGroupId = @DiscountGroupId AND
		(d.CurrencyId = 0 OR d.CurrencyId = c.CurrencyId) -- all currency = 0

END
GO