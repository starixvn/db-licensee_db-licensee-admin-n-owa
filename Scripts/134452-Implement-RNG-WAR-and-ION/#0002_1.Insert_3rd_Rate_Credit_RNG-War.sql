/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200615@Parsons
	DB: DBCUST.bodb_licensee
	Description: Add 3rd credit Rate settings for RNG-WAR Casino
*/
USE bodb_licensee
GO

DECLARE @RNGWarProductId INT = 50
DECLARE @HasInsertSetting BIT = 0;
DECLARE @RNGWarProductCode VARCHAR(10) = 'RNGW'

-- 3rd party
IF NOT EXISTS (SELECT PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @RNGWarProductCode AND PartyType = 3)
BEGIN 
	INSERT bodb_licensee.dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID, SetupName)
	VALUES (@RNGWarProductCode, 'RNG War', 3, null, null)
END

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = @RNGWarProductCode)

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25, 30) 
									  AND ToParty = @3rdPartyId
									  AND ProductID = @RNGWarProductId)
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
	VALUES (@RNGWarProductId, 25, @3rdPartyId, 0, 0.04, 1, '2020-06-01', '2050-01-01', null, null, null, null, null, null),
		   (@RNGWarProductId, 30, @3rdPartyId, 0, 0.04, 1, '2020-06-01', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25, 30) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @RNGWarProductId 
END