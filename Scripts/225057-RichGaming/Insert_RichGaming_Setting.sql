/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250502@Corbin
	DB: DBCUST.bodb_licensee
	Description: Add setting rate RichGaming Terms [RedmineID: #225057]
*/

USE bodb_licensee
GO

-- Insert new 3rd Party (Type = 3)
IF NOT EXISTS ( SELECT 1 FROM dbo.OAS_Party WITH (NOLOCK) WHERE PartyName = 'RGRNG' AND PartyType = 3 )
	INSERT INTO dbo.OAS_Party (PartyName, Description, PartyType)
	VALUES ('RGRNG', 'RGRNG', 3)

DECLARE @PartyId INT
SELECT @PartyId = PartyId FROM dbo.OAS_Party WITH (NOLOCK) WHERE PartyName = 'RGRNG' AND PartyType = 3

-- insert 3rd Rate (PaytoSupplier)
INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
SELECT t.ProductId, t.FromParty, t.ToParty, t.ParentChargeId, t.Rate, t.ChargeType, t.FromDate, t.ToDate
FROM (
	SELECT 108 AS ProductId, p.PartyId AS FromParty, @PartyId AS ToParty, 0 AS ParentChargeId, 0.55 Rate, 1 AS ChargeType, '2025-05-08' AS FromDate, '2050-01-01' AS ToDate 
	FROM (VALUES (1), (9), (11), (98), (962), (1235), (25), (30)) AS p (PartyId)
) t
	LEFT JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON t.ProductId = c.ProductId AND t.FromParty = c.FromParty AND t.ToParty = c.ToParty AND t.FromDate <= c.ToDate AND t.ToDate >= c.FromDate
WHERE c.ProductId IS NULL
	
-- insert System Mapping (SystemId = 2: OA)
INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
SELECT c.ChargeId, 2 AS SystemId
FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
	LEFT JOIN dbo.LA_ChargeInfo_SystemMapping s WITH (NOLOCK) ON c.ChargeId = s.ChargeId AND s.SystemId = 2
WHERE c.ProductId = 108
	AND c.FromParty IN (1, 9, 11, 98, 962, 1235, 25, 30)
	AND c.ToParty = @PartyId
	AND s.ChargeId IS NULL

-- Insert Credit ChargeRate
DECLARE @HasInsertSetting BIT = 0;
IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH (NOLOCK)
							   WHERE FromParty IN (25, 30) 
								 AND ToParty = 1
								 AND ProductID = 108)
BEGIN
	-- Insert setting rate for Credit
	INSERT INTO OAS_ChargeInfo([ProductID]
								,[FromParty]
								,[ToParty]
								,[ParentChargeID]
								,[Rate]
								,[ChargeType]
								,[FromDate]
								,[ToDate]
								,[MinAmount]
								,[MaxAmount]
								,[Remark]
								,[BaseCurrencyId]
								,[FirstOfBilling]
								,[BasisOfBilling])
	VALUES(108, 25, 1, 0, 0, 1, '2025-05-08', '2050-01-01', NULL, NULL, NULL, NULL, NULL, NULL),
		  (108, 30, 1, 0, 0, 1, '2025-05-08', '2050-01-01', NULL, NULL, NULL, NULL, NULL, NULL)

	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty IN (25, 30) 
	  AND ToParty = 1
	  AND ProductID = 108 
END
