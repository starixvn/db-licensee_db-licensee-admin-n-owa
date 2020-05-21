/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

USE bodb_licensee
GO

/*
	Created: 20200508@Parsons
	DB: DBCUST
	Description: Add 3rd deposit rate settings Sexy Gaming [#132665]
*/

DECLARE @BillingGroups AS TABLE(PartyID INT)
DECLARE @SexyGamingProductId INT = 45
DECLARE @HasInsertSetting BIT = 0

-- for deposit billing groups
INSERT INTO @BillingGroups(PartyID)
VALUES(1), (9), (11), (98)

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = 'SXG')
IF NOT EXISTS (SELECT TOP 1 ChargeID FROM OAS_ChargeInfo WITH (NOLOCK) WHERE ProductID = @SexyGamingProductId AND FromParty IN (1,9,11,98) AND ToParty = @3rdPartyId )
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
	SELECT @SexyGamingProductId, b.PartyID, @3rdPartyId, 0, 0.03, 1, '2020-05-20', '2050-01-01', null, null, null, null, null, null
	FROM @BillingGroups b
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty IN (SELECT PartyID FROM @BillingGroups) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @SexyGamingProductId 
END