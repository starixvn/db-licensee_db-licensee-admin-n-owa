/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201220@Parsons
	DB: DBCUST.bodb_licensee
	Description: Add setting rate from credit to OW for VS3.
*/

USE bodb_licensee
GO

DECLARE @VS3ProductId INT = 49
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @VS3ProductId)
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
	VALUES(@VS3ProductId, 25, 1, 0, 0, 1, '2020-10-31', '2050-01-01', null, null, null, null, null, null),
		  (@VS3ProductId, 30, 1, 0, 0, 1, '2020-10-31', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @VS3ProductId 
END