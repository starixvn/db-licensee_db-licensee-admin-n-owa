/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200610@Happy
	DB: DBCUST.bodb_licensee
	Description: Add 3rd credit Rate settings for ION Casino
*/

USE bodb_licensee
GO

DECLARE @IONProductId INT = 52
DECLARE @HasInsertSetting BIT = 0;
DECLARE @IONProductCode VARCHAR(10) = 'ION'

-- 3rd party
IF NOT EXISTS (SELECT PartyID FROM bodb_licensee.dbo.OAS_Party WHERE PartyName = @IONProductCode AND PartyType = 3)
BEGIN 
	INSERT bodb_licensee.dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID, SetupName)
	VALUES (@IONProductCode, 'ION Casino', 3, null, null)
END

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WHERE p.PartyType = 3 and p.PartyName = @IONProductCode)

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo 
							   WHERE FromParty IN (25, 30) 
									  AND ToParty = @3rdPartyId
									  AND ProductID = @IONProductId)
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
	VALUES (@IONProductId, 25, @3rdPartyId, 0, 0.05, 1, '2020-06-16', '2050-01-01', null, null, null, null, null, null),
		   (@IONProductId, 30, @3rdPartyId, 0, 0.05, 1, '2020-06-16', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo 
	WHERE FromParty IN (25, 30) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @IONProductId 
END