/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20241209@Sally
	DB: DBCUST.bodb_Licensee
	Task: Vendor Payment report - Apply the new charge rate with vendors for some 3rd products [#214829]
	Phase 1: change  6/8
	 - Yeebet				- Template 7	ProductId 76
	 - IBCBet Live Casino	- Template 1	ProductId 46
	 - AdvantPlay			- Template 1	ProductId 67
	 - AdvantPlay Mini		- Template 1	ProductId 68
	 - SA Gaming			- Template 10	ProductId 39
	 - Playtech				- Template 18	ProductId 100
*/
USE bodb_Licensee
GO

DECLARE @NewTermsEffected TABLE (ToPartyId INT, ProductId INT, FromDate DATE, ToDate DATE,  Rate MONEY)
DECLARE @ChargeIds TABLE (ChargeId_New INT, ProductId INT)
DECLARE @ChargeLastedInfo TABLE (ChargeId_Old INT, ProductId INT, ChargeType INT, EndDate DATE)
;WITH CTE_ProductInfo AS (
	SELECT ProductPrefix AS ProductCode, ProductName, Productid
	FROM dbo.Product3rd WITH(NOLOCK)
	WHERE ProductName in ('YeeBet', 'IBCBet Live Casino', 'SA Gaming', 'AdvantPlay', 'AdvantPlay Mini', 'Playtech')
),
CTE_ToPartyIds AS (
	SELECT p.PartyID AS ToPartyId
		,t.ProductId
		,t.ProductCode
		,t.ProductName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		CROSS APPLY(
		SELECT ProductCode, ProductName, ProductId
		FROM CTE_ProductInfo
		WHERE ProductCode = p.PartyName
	)t
)
INSERT INTO @NewTermsEffected(ToPartyId, ProductId, FromDate, ToDate, Rate)
SELECT p.ToPartyId,p.Productid, t.FromDate, t.ToDate, t.Rate
FROM CTE_ToPartyIds p
	INNER JOIN ( 
		SELECT 'YeeBet' AS ProductName, '2024-12-01' AS FromDate, '2050-01-01' AS ToDate, 0.03 AS Rate
		UNION ALL
		SELECT 'IBCBet Live Casino' AS ProductName, '2024-12-01' AS FromDate, '2050-01-01' AS ToDate, 0.04 AS Rate
		UNION ALL
		SELECT'AdvantPlay' AS ProductName, '2024-12-01' AS FromDate, '2050-01-01' AS ToDate, 0.04 AS Rate
		UNION ALL
		SELECT'AdvantPlay Mini' AS ProductName, '2024-12-01' AS FromDate, '2050-01-01' AS ToDate, 0.04 AS Rate
		UNION ALL
		SELECT 'SA Gaming' AS ProductName, '2025-01-01' AS FromDate, '2050-01-01' AS ToDate, 0.008 AS Rate--, 11 ChargeType
		UNION ALL
		SELECT'Playtech' AS ProductName, '2024-12-01' AS FromDate, '2050-01-01' AS ToDate, 0.05 AS Rate
	)t on p.ProductName = t.ProductName
	
BEGIN
	INSERT INTO @ChargeLastedInfo(ChargeId_Old, ProductId, ChargeType, EndDate)
		SELECT  TOP 1 WITH TIES c.ChargeId, c.ProductId, c.ChargeType,  DATEADD(DAY, -1, ne.FromDate) AS EndDate
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
		INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId	
		ORDER BY ROW_NUMBER() OVER(PARTITION BY c.FromParty, c.ToParty, c.ChargeType ORDER BY c.ToDate DESC)
	
	IF NOT EXISTS(
		SELECT TOP 1 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
												AND ne.FromDate = c.FromDate AND ne.ToDate = c.ToDate
		WHERE c.ProductId IN (46, 67, 68, 100)
			AND c.ChargeType = 1
	)
	BEGIN		
		--SELECT ci.EndDate,'IBCBet Live Casino, AdvantPlay, AdvantPlay Mini, Playtech', *
		UPDATE c SET ToDate = ci.EndDate
		FROM dbo.OAS_ChargeInfo c WITH (UPDLOCK, ROWLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
		WHERE c.ProductId IN (46, 67, 68, 100)-- IBCBet Live Casino, AdvantPlay, AdvantPlay Mini, Playtech	
			AND c.ChargeType = 1
	END
	
	IF NOT EXISTS(
		SELECT TOP 1 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
												AND ne.FromDate = c.FromDate AND ne.ToDate = c.ToDate
		WHERE c.ProductId  = 76
	)
	BEGIN
		--SELECT ci.EndDate, 'Yeebet',ne.*, c.*
		UPDATE c SET ToDate = ci.EndDate
		FROM dbo.OAS_ChargeInfo c WITH (UPDLOCK, ROWLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
		WHERE c.ProductId = 76	--- Yeebet
	END

	INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	OUTPUT INSERTED.ChargeID, INSERTED.ProductID INTO @ChargeIds (ChargeId_New, ProductId)
	SELECT t.ProductID, t.FromParty, t.ToParty, t.ParentChargeID, t.Rate, t.ChargeType, t.FromDate, t.ToDate, NULL MinAmount, NULL MaxAmount,  NULL Remark, NULL BaseCurrencyId, NULL FirstOfBilling, NULL BasisOfBilling
	FROM (
		SELECT c.ProductID, c.FromParty, c.ToParty, c.ParentChargeID, ne.Rate, c.ChargeType, ne.FromDate, ne.ToDate
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON c.ToParty = ne.ToPartyId AND c.ProductID = ne.ProductId
		WHERE c.ChargeType = 1
			AND c.ProductId IN (76, 46, 67, 68, 100) --Yeebet, IBCBet Live Casino, AdvantPlay, AdvantPlay Mini, Playtech
	)t
		LEFT JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON c.ToParty = t.ToParty 
													AND c.ProductID = t.ProductId 
													AND c.ChargeType  = t.ChargeType
													AND t.FromDate = c.FromDate AND t.ToDate = c.ToDate
	WHERE c.ProductId IS NULL

	---- SA Gaming
	IF NOT EXISTS(
		SELECT TOP 1 1
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
												AND ne.FromDate = c.FromDate AND ne.ToDate = c.ToDate
		WHERE c.ProductId = 39
			AND c.ChargeType = 11
	)
	BEGIN
		--SELECT ci.EndDate,'SA Gaming', *
		UPDATE c SET ToDate = ci.EndDate
		FROM dbo.OAS_ChargeInfo c WITH (UPDLOCK, ROWLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON ne.ToPartyId = c.ToParty AND c.ProductId = ne.ProductId 
		WHERE c.ProductId = 39
			AND c.ChargeType = 11
	END

	INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	OUTPUT INSERTED.ChargeID, INSERTED.ProductID INTO @ChargeIds (ChargeId_New, ProductId)
	SELECT t.ProductID, t.FromParty, t.ToParty, t.ParentChargeID, t.Rate, t.ChargeType, t.FromDate, t.ToDate, NULL MinAmount, NULL MaxAmount,  NULL Remark, NULL BaseCurrencyId, NULL FirstOfBilling, NULL BasisOfBilling
	FROM (
		SELECT c.ProductID, c.FromParty, c.ToParty, c.ParentChargeID, ne.Rate, c.ChargeType, ne.FromDate, ne.ToDate
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN @ChargeLastedInfo ci ON ci.ChargeId_Old = c.ChargeID
			INNER JOIN @NewTermsEffected ne ON c.ToParty = ne.ToPartyId AND c.ProductID = ne.ProductId
		WHERE c.ChargeType = 11
			AND c.ProductId = 39
	)t
		LEFT JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON c.ToParty = t.ToParty 
													AND c.ProductID = t.ProductId 
													AND c.ChargeType  = t.ChargeType
													AND t.FromDate = c.FromDate AND t.ToDate = c.ToDate
	WHERE c.ProductId IS NULL

	INSERT INTO dbo.LA_ChargeInfo_SystemMapping(ChargeID,SystemID)
	SELECT ChargeId_New, 2 AS SystemID
	FROM @ChargeIds	
	
END

