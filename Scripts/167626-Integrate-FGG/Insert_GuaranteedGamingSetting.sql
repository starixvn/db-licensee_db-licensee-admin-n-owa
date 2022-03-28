/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20220328@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate Guaranteed Gaming Terms:
*/

USE bodb_licensee
GO

-- DELETE FROM OAS_ChargeInfo WITH(ROWLOCK) WHERE ProductID = 70
-- SELECT * FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID = 70

DECLARE @FGGProductId INT = 70
DECLARE @HasInsertSetting BIT = 0;
DECLARE @FGGPlayCode VARCHAR(10) = 'FGGL'


-- 3rd party
IF NOT EXISTS (SELECT PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @FGGPlayCode AND PartyType = 3)
BEGIN 
	INSERT bodb_licensee.dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID, SetupName)
	VALUES (@FGGPlayCode, 'FGGL', 3, null, null)
END

------------------------------------------------------

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 AND p.PartyName = @FGGPlayCode)

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) 
							   WHERE FromParty IN (25, 30) 
									  AND ToParty = @3rdPartyId
									  AND ProductID = @FGGProductId)
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
	VALUES (@FGGProductId, 25, @3rdPartyId, 0, 0.05, 1, '2022-01-01', '2050-01-01', null, null, null, null, null, null),
		   (@FGGProductId, 30, @3rdPartyId, 0, 0.05, 1, '2022-01-01', '2050-01-01', null, null, null, null, null, null),
		   (@FGGProductId, 25, @3rdPartyId, 0, 0.008, 11, '2022-01-01', '2050-01-01', null, null, null, null, null, null), -- CommRate
		   (@FGGProductId, 30, @3rdPartyId, 0, 0.008, 11, '2022-01-01', '2050-01-01', null, null, null, null, null, null)  -- CommRate
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (25, 30) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @FGGProductId 
END


GO
-----  Add setting rate from credit to OW for AdvantPlay.
DECLARE @FGGProductId INT = 70
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @FGGProductId)
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
	VALUES(@FGGProductId, 25, 1, 0, 0, 1, '2022-01-01', '2050-01-01', null, null, null, null, null, null),
		  (@FGGProductId, 30, 1, 0, 0, 1, '2022-01-01', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @FGGProductId 
END

GO
----
DECLARE @BillingGroups AS TABLE(PartyID INT)
DECLARE @FGGProductId INT = 70
DECLARE @HasInsertSetting BIT = 0

-- for deposit billing groups
INSERT INTO @BillingGroups(PartyID)
VALUES(1), (9), (11), (98)

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = 'FGGL')
IF NOT EXISTS (SELECT TOP 1 ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID = @FGGProductId AND FromParty IN (1,9,11,98) AND ToParty = @3rdPartyId )
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
	SELECT @FGGProductId, b.PartyID, @3rdPartyId, 0, 0.05, 1, '2022-01-01', '2050-01-01', null, null, null, null, null, null
	FROM @BillingGroups b
	

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
	SELECT @FGGProductId, b.PartyID, @3rdPartyId, 0, 0.008, 11, '2022-01-01', '2050-01-01', null, null, null, null, null, null
	FROM @BillingGroups b

	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (SELECT PartyID FROM @BillingGroups) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @FGGProductId 
END