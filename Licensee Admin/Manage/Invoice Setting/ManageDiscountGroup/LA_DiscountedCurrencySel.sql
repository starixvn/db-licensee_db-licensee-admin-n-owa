/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_DiscountedCurrencySel]
	@PartyId			INT,
	@ProductIds			VARCHAR(100)
AS
/*  
	 Created: 20181116@Parsons [#99694]
	 Task : Configure discount settings by currency
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20181116@Parsons: Configure discount settings by currency [#99694]

	 Params:

	 Explannation: EXEC LA_DiscountedCurrencySel @PartyId = 14, @ProductIds = N'0,4,8'
*/
BEGIN
	SET NOCOUNT ON

	--Region: Get all currencies of party 
	DECLARE @CurrenciesOfLicensee TABLE (CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	
	INSERT INTO @CurrenciesOfLicensee(CurrencyId, CurrencyCode, CurrencyName)
	SELECT DISTINCT lc.Currency, e.Code, CASE WHEN lc.Currency = 51 THEN 'VND' ELSE e.currency END AS CurrencyName
	FROM dbo.f_SelLicenseeCust(0) AS lc
	INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID 
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
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
	;WITH cte_DiscountSetting AS( 
		SELECT p.ProductId, MAX(a.DiscountGroupId) AS DiscountGroupId
		FROM LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN LA_DiscountGroupProduct p WITH(NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId 
																AND p.ProductId IN (SELECT val FROM bodb02.dbo.strSplit(@ProductIds, ','))
		WHERE a.PartyID = @PartyId
		GROUP BY p.ProductId )

	SELECT CONVERT(INT, val) AS ProductId, STUFF((
				SELECT ', ' + ISNULL(CAST(c.CurrencyCode AS VARCHAR), '')
					FROM @CurrenciesOfLicensee c
					INNER JOIN LA_DiscountGroupCurrency dc WITH(NOLOCK) ON 
							dc.PartyID = @PartyId AND
							(dc.CurrencyId = 0 OR dc.CurrencyId = c.CurrencyId) -- all currency = 0
					INNER JOIN cte_DiscountSetting ds ON ds.DiscountGroupId = dc.DiscountGroupId AND ds.ProductId = val
				FOR XML PATH (''))
			  , 1, 2, '') AS CurrencyNames
	FROM bodb02.dbo.strSplit(@ProductIds, ',')
	-- End Region: select discounted currency of party
END
GO