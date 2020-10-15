/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200909@Parsons
	DB: DBCUST.bodb_licensee
	Description: Add setting rate from credit to OW for PGS.
*/

USE bodb_licensee
GO

DECLARE @PGSProductId INT = 55
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @PGSProductId)
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
	VALUES(@PGSProductId, 25, 1, 0, 0, 1, '2020-09-30', '2050-01-01', null, null, null, null, null, null),
		  (@PGSProductId, 30, 1, 0, 0, 1, '2020-09-30', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @PGSProductId 
END