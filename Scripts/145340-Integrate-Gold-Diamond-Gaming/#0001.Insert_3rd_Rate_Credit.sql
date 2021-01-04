/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201203@Happy
	DB: DBCUST.bodb_licensee
	Description: Add 3rd credit Rate settings for GDG
*/

USE bodb_licensee
GO

DECLARE @GDGProductId INT = 59
DECLARE @HasInsertSetting BIT = 0;
DECLARE @GDGProductCode VARCHAR(10) = 'GDG'

DECLARE @AffectedDate DATE = '2020-12-03'
DECLARE @CreditService_ChargeType INT = 10
DECLARE @CreditService_ChargeRate DECIMAL(4, 3) = 0.035

DECLARE @RollingCommission_ChargeType INT = 11
DECLARE @RollingCommission_ChargeRate DECIMAL(4, 3) = 0.01

-- 3rd party
IF NOT EXISTS (SELECT PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @GDGProductCode AND PartyType = 3)
BEGIN 
	INSERT bodb_licensee.dbo.OAS_Party (PartyName, [Description], PartyType, OldRefID, SetupName)
	VALUES (@GDGProductCode, 'GDG', 3, null, null)
END

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = @GDGProductCode)

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) 
							   WHERE FromParty IN (25, 30) 
									  AND ToParty = @3rdPartyId
									  AND ProductID = @GDGProductId)
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
	VALUES -- 1. Service charge rate
			(@GDGProductId, 25, @3rdPartyId, 0, @CreditService_ChargeRate, @CreditService_ChargeType, @AffectedDate, '2050-01-01', null, null, null, null, null, null)
		   ,(@GDGProductId, 30, @3rdPartyId, 0, @CreditService_ChargeRate, @CreditService_ChargeType, @AffectedDate, '2050-01-01', null, null, null, null, null, null)
		   
		   --2. Rolling commission rate
		   ,(@GDGProductId, 25, @3rdPartyId, 0, @RollingCommission_ChargeRate, @RollingCommission_ChargeType, @AffectedDate, '2050-01-01', null, null, null, null, null, null)
		   ,(@GDGProductId, 30, @3rdPartyId, 0, @RollingCommission_ChargeRate, @RollingCommission_ChargeType, @AffectedDate, '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (25, 30) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @GDGProductId 
END