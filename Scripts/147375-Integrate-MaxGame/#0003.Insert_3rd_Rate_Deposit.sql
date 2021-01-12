/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210112@Happy
	DB: DBCUST
	Description: Add 3rd deposit rate settings MaxGame
*/
USE bodb_licensee
GO

DECLARE @BillingGroups AS TABLE(PartyID INT)
DECLARE @MXGProductId INT = 60
DECLARE @HasInsertSetting BIT = 0

-- for deposit billing groups
INSERT INTO @BillingGroups(PartyID)
VALUES(1), (9), (11), (98)

DECLARE @3rdPartyId INT = (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 3 and p.PartyName = 'MXG')
IF NOT EXISTS (SELECT TOP 1 ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID = @MXGProductId AND FromParty IN (1,9,11,98) AND ToParty = @3rdPartyId )
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
	SELECT @MXGProductId, b.PartyID, @3rdPartyId, 0, 0.03, 1, '2021-01-12', '2050-01-01', null, null, null, null, null, null
	FROM @BillingGroups b
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK) 
	WHERE FromParty IN (SELECT PartyID FROM @BillingGroups) 
		  AND ToParty = @3rdPartyId
		  AND ProductID = @MXGProductId 
END