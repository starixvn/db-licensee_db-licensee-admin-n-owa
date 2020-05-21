/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

USE bodb_licensee
GO

/*
	Created: 20200512@Parsons
	DB: DBCUST
	Description: Add setting rate from credit to OW for Saba.Club product
*/

DECLARE @SBCProductId INT = 42
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH (NOLOCK) 
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @SBCProductId)
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
	VALUES(@SBCProductId, 25, 1, 0, 0, 1, '2020-05-20', '2050-01-01', null, null, null, null, null, null),
		  (@SBCProductId, 30, 1, 0, 0, 1, '2020-05-20', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @SBCProductId 
END