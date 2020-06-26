/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200610@Happy
	DB: DBCUST.bodb_licensee
	Description: Add setting rate from credit to OW for ION Casino.
*/

USE bodb_licensee
GO

DECLARE @IONProductId INT = 52
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo 
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @IONProductId)
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
	VALUES(@IONProductId, 25, 1, 0, 0, 1, '2020-06-16', '2050-01-01', null, null, null, null, null, null),
		  (@IONProductId, 30, 1, 0, 0, 1, '2020-06-16', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo 
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @IONProductId 
END