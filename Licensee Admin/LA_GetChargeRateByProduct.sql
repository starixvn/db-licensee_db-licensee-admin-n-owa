/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GetChargeRateByProduct]
	@PartyId	INT
	,@ProductId	INT
	,@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	 Created: 20211101@Percy
	 DB: DBLIC-bodb_licensee
	 Task: Get Charge Rate by Product
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT TOP 1 Rate AS ChargeRate
	FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty = @PartyId AND ToParty IN (1, 9, 11, 98) -- to OW
		AND ProductId = @ProductId AND ChargeType = 1
		AND FromDate <= @ToDate AND ToDate >= @FromDate
END
GO