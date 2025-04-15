--------------------------------------------------------------------------------------------------------------------

/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250415@Lionel
	DB: DBCUST.bodb_licensee
	Description: Add setting rate Microgaming Live Terms
*/

USE bodb_licensee
GO


DECLARE @MGLCProductId INT = 107
DECLARE @HasInsertSetting BIT = 0;
DECLARE @ProductCode VARCHAR(10) = 'MGLC'


-- 3rd party
IF NOT EXISTS (SELECT PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @ProductCode AND PartyType = 3)
BEGIN 
	INSERT bodb_licensee.dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID, SetupName)
	VALUES (@ProductCode, 'MGLC', 3, null, null)
END

------------------------------------------------------

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 AND p.PartyName = @ProductCode)

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) 
							   WHERE FromParty IN (25, 30) 
									  AND ToParty = @3rdPartyId
									  AND ProductID = @MGLCProductId)
BEGIN
	-------**** Insert 3rd Rate for Credit ****---------
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
	VALUES (@MGLCProductId, 25, @3rdPartyId, 0, 0.05, 1, '2025-03-01', '2050-01-01', null, null, null, null, null, null),
		   (@MGLCProductId, 30, @3rdPartyId, 0, 0.05, 1, '2025-03-01', '2050-01-01', null, null, null, null, null, null)
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (25, 30) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @MGLCProductId 
END


GO
----
DECLARE @MGLCProductId INT = 107
DECLARE @BillingGroups AS TABLE(PartyID INT)
DECLARE @HasInsertSetting BIT = 0;

-- for deposit billing groups
INSERT INTO @BillingGroups(PartyID)
VALUES(1), (9), (11), (98), (962), (1235)

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = 'MGLC')
IF NOT EXISTS (SELECT TOP 1 ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID = @MGLCProductId AND FromParty IN (1,9,11,98,962,1235) AND ToParty = @3rdPartyId )
BEGIN
	-------**** Insert 3rd Rate for Deposit ****---------
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
	SELECT @MGLCProductId, b.PartyID, @3rdPartyId, 0, 0.05, 1, '2025-03-01', '2050-01-01', null, null, null, null, null, null
	FROM @BillingGroups b

	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (SELECT PartyID FROM @BillingGroups) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @MGLCProductId 
END