/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Scripts Discount Tier
*/
USE bodb_Licensee 
GO


DECLARE @ChargeRate_PartyTable TABLE(PartyID INT, PartyName VARCHAR(100), BaseCurrencyId INT, DiscountGroupId INT, DiscountGroupName NVARCHAR(100), MaxDateOfProductSettings DATE, NumberOfDiscountTiers INT)

INSERT INTO @ChargeRate_PartyTable(PartyID, PartyName, BaseCurrencyId, MaxDateOfProductSettings)
SELECT pd.PartyID, p.PartyName, pd.BaseCurrencyId, MAX(ToDate) AS MaxDateOfProductSettings
FROM OAS_ChargeInfo ci WITH(NOLOCK)
INNER JOIN OAS_Party p WITH(NOLOCK) ON ci.FromParty = p.PartyID
INNER JOIN OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
GROUP BY pd.PartyID, p.PartyName, pd.BaseCurrencyId
ORDER BY p.PartyName

;WITH cte_DiscountGroup AS
(
	SELECT t1.PartyID, t2.DiscountGroupId, t2.DiscountGroupName, COUNT(d.DiscountGroupDetailId) NumberOfDiscountTiers
	FROM @ChargeRate_PartyTable t1
	CROSS APPLY
	(
		SELECT TOP 1 a.DiscountGroupId, h.DiscountGroupName
		FROM LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		WHERE a.PartyID = t1.PartyID AND h.ToDate >= GETDATE()
		ORDER BY h.ToDate DESC
	)t2
	INNER JOIN LA_DiscountGroupDetail d WITH(NOLOCK) ON t2.DiscountGroupId = d.DiscountGroupId
	GROUP BY t1.PartyID, t2.DiscountGroupId, t2.DiscountGroupName
)
UPDATE c
SET c.NumberOfDiscountTiers = cte.NumberOfDiscountTiers,
c.DiscountGroupId = cte.DiscountGroupId,
c.DiscountGroupName = cte.DiscountGroupName
FROM cte_DiscountGroup cte
INNER JOIN @ChargeRate_PartyTable c ON cte.PartyID = c.PartyID
WHERE cte.DiscountGroupId IS NOT NULL

SELECT PartyID, PartyName, BaseCurrencyId, DiscountGroupId, DiscountGroupName, MaxDateOfProductSettings, NumberOfDiscountTiers
FROM @ChargeRate_PartyTable