/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201203@Happy
	DB: DBCUST.bodb_licensee
	Description: Add setting rate from credit to OW for GDG.
*/

USE bodb_licensee
GO

DECLARE @GDGProductId INT = 59
DECLARE @HasInsertSetting BIT = 0;

IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = @GDGProductId)
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
	VALUES(@GDGProductId, 25, 1, 0, 0.01, 11, '2020-12-03', '2050-01-01', null, null, null, null, null, null),
		  (@GDGProductId, 30, 1, 0, 0.01, 11, '2020-12-03', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = @GDGProductId 
END