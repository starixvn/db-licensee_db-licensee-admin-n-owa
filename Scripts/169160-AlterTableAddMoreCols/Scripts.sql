/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20230202@Danny
	DB: DBCUST.bodb_Licensee
	Task: TIP - Player tips [#169160]
	Description: Insert Into LA_InvoiceItemType record: Player tips
*/
USE bodb_Licensee
GO

ALTER TABLE LA_DiscountGroupDetail ADD ChargeRateAfterDiscount MONEY NULL
ALTER TABLE LA_DiscountGroupDetail ALTER COLUMN Rate MONEY NULL

-- Handle old data
; WITH t AS
(
	SELECT lg.* , ld.FromDate, ld.ToDate, rate.ChargeRate, rate.ChargeRate - lg.Rate AS ChargerateAfterDiscount_new
	FROM dbo.LA_DiscountGroupHeader ld  WITH(NOLOCK) 
	INNER JOIN dbo.LA_DiscountGroupDetail lg WITH(NOLOCK) ON ld.DiscountGroupId = lg.DiscountGroupId
	CROSS APPLY (
		SELECT TOP 1 oc.Rate ChargeRate
		FROM dbo.LA_DiscountGroupCurrency lc WITH(NOLOCK)
		INNER JOIN dbo.OAS_ChargeInfo oc WITH (NOLOCK) ON lc.PartyID = oc.FromParty 
												AND oc.ToParty IN (1, 9, 11, 98) 
												AND oc.ProductID = 0 
												AND oc.ChargeType = 1
												AND oc.FromDate <= ld.ToDate AND oc.ToDate >= ld.FromDate
		WHERE lc.DiscountGroupId = ld.DiscountGroupId
	) rate
	WHERE ld.DiscountGroupType IN (3,13)
	
)UPDATE x
SET x.ChargeRateAfterDiscount = t.ChargeRateAfterDiscount_new
FROM LA_DiscountGroupDetail x
INNER JOIN t ON x.DiscountGroupDetailId = t.DiscountGroupDetailId
WHERE t.ChargerateAfterDiscount_new >= 0


