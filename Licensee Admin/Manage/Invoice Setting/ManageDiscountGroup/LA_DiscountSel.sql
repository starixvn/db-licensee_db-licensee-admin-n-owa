/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountSel]
AS
/*  
	 Created: 20180627@Parsons [#94282]
	 Task: Enhance Manage Discount group function to support more discount schemes
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20180627@Parsons: Get discount groups info [#94282]
		- 20211101@Percy: Support Discount on Lic WL - Do not show discount group from CutOffDate [RedmineID: #162158]

	 Params:

	 Explannation: EXEC LA_DiscountSel
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()

	SELECT  h.DiscountGroupId, 
			h.DiscountGroupName,
			ISNULL(ex.Code, '') AS CurrencyName,
			h.FromDate,
			h.ToDate,
			h.DiscountGroupType, 
			STUFF((
				SELECT ', ' + ISNULL(CAST(ppp.ProductName AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
					LEFT JOIN dbo.LA_f_Products3rd('') ppp ON pp.ProductId = ppp.Productid
				WHERE pp.DiscountGroupId = h.DiscountGroupId AND (CalculationType = 1 OR  CalculationType = 10)
				FOR XML PATH (''))
			  , 1, 2, '') AS CalculationProductList, 
			STUFF((
			SELECT ', ' + ISNULL(CAST(ppp.ProductName AS VARCHAR), '')
			FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
				LEFT JOIN dbo.LA_f_Products3rd('') ppp ON pp.ProductId = ppp.Productid
			WHERE pp.DiscountGroupId = h.DiscountGroupId AND (CalculationType = 0 OR  CalculationType = 10)
			FOR XML PATH (''))
			, 1, 2, '') AS DiscountProductList, 
			STUFF((
			SELECT ', ' + CASE WHEN ISNULL(d.BrandName, '') = '' THEN ISNULL(CAST(pp.PartyName AS VARCHAR), '') ELSE ISNULL(CAST(d.BrandName AS VARCHAR), '') END
			FROM dbo.LA_DiscountGroupAssignment aa WITH (NOLOCK)
				LEFT JOIN dbo.OAS_Party pp WITH(NOLOCK) ON aa.PartyID = pp.PartyID
				LEFT JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON aa.PartyID = d.PartyID
			WHERE aa.DiscountGroupId = h.DiscountGroupId
			FOR XML PATH (''), ROOT('str'), TYPE 
				).value('/str[1]','VARCHAR(MAX)') 
			, 1, 2, '') AS PayerList
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		LEFT JOIN bodb02.dbo.Exchange ex WITH(NOLOCK) ON h.CurrencyId = ex.ExchangeId
	WHERE DiscountGroupType IN (1, 3, 11, 13)
		AND h.ToDate < @CutOffDate
	GROUP BY h.DiscountGroupId, 
			h.DiscountGroupName,
			ISNULL(ex.Code, ''),
			h.FromDate,
			h.ToDate,
			h.DiscountGroupType

	-- Get rate settings 
	SELECT h.DiscountGroupId, d.FromAmount, d.ToAmount, d.Rate	
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		 INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
	WHERE DiscountGroupType IN (1, 3, 11, 13)
	ORDER BY DiscountGroupDetailId, FromAmount
END
GO