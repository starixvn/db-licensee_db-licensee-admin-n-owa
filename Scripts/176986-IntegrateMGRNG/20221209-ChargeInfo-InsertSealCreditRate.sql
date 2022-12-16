/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20221209@Danny
	DB: DBCUST-bodb_Licensee
	Task: Insert Credit charge rate for SEAL Entertainment
	ProductId = 72
*/
use bodb_Licensee
go


-- Insert Credit ChargeRate
DECLARE @HasInsertSetting BIT = 0;
IF NOT EXISTS (SELECT ChargeID FROM OAS_ChargeInfo WITH(NOLOCK)
							   WHERE FromParty IN (25,30) 
									  AND ToParty = 1
									  AND ProductID = 72)
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
	VALUES(72, 25, 1, 0, 0, 1, '2022-09-29', '2050-01-01', null, null, null, null, null, null),
		  (72, 30, 1, 0, 0, 1, '2022-09-29', '2050-01-01', null, null, null, null, null, null)
	
	SET @HasInsertSetting = 1
END

IF @HasInsertSetting = 1
BEGIN
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty IN (25,30) 
		  AND ToParty = 1
		  AND ProductID = 72 
END

