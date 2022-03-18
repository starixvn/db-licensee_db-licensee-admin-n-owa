/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountedCurrencySel]
	@PartyId			INT,
	@ProductIds			VARCHAR(100)
AS
/*  
	 Created: 20181116@Parsons [#99694]
	 Task : Configure discount settings by currency
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20181116@Parsons: Configure discount settings by currency [#99694]
		- 20200225@Parsons: Support-HID-currency [#128856]
		- 20211101@Percy: Return applied currencies [RedmineID: #162158]

	 Params:

	 Explannation: EXEC LA_DiscountedCurrencySel @PartyId = 14, @ProductIds = N'0,4,8'
*/
BEGIN
	SET NOCOUNT ON

	--Region: Get all currencies of party 
	DECLARE @CurrenciesOfLicensee TABLE (CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	
	INSERT INTO @CurrenciesOfLicensee(CurrencyId, CurrencyCode, CurrencyName)
	SELECT DISTINCT lc.Currency, 
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
		SELECT CurrencyCode
	    FROM @CurrenciesOfLicensee
	    GROUP BY CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.CurrencyCode = c2.CurrencyCode
	-- End Region: Get all currencies of party 

	-- Region: select discounted currency of party
	;WITH CTE_DiscountSetting AS( 
		SELECT p.ProductId, MAX(a.DiscountGroupId) AS DiscountGroupId
		FROM LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId AND h.DiscountGroupType IN (1, 3, 11, 13) 
		INNER JOIN LA_DiscountGroupProduct p WITH(NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId 
																AND p.ProductId IN (SELECT val FROM dbo.strSplit(@ProductIds, ','))
		WHERE a.PartyID = @PartyId
		GROUP BY p.ProductId )

	SELECT CONVERT(INT, s.val) AS ProductId, STUFF((
				SELECT ', ' + ISNULL(CurrencyCode, '')
				FROM CTE_DiscountSetting ds
					INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON ds.DiscountGroupId = h.DiscountGroupId
					INNER JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON h.DiscountGroupId = c.DiscountGroupId AND c.PartyID = @PartyId AND (h.DiscountGroupType IN (1, 11) OR c.CalculationType IN (2, 3))
					INNER JOIN @CurrenciesOfLicensee tc ON (c.CurrencyId = 0 OR c.CurrencyId = tc.CurrencyId)
				FOR XML PATH (''))
			  , 1, 2, '') AS CurrencyNames
	FROM dbo.strSplit(@ProductIds, ',') s
	-- End Region: select discounted currency of party
END
GO