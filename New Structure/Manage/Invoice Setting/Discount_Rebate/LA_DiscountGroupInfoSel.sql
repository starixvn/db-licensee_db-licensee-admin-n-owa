USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupInfoSel @DiscountType TINYINT
	, @GroupName VARCHAR(100) = ''
AS
/*  
	 Created: 20150422@Patrick
	 Task : Get discount group info
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	IF ISNULL(@GroupName, '') = ''
		SET @GroupName = NULL

	SELECT h.DiscountGroupId, h.DiscountGroupName, h.CurrencyId, h.FromDate, h.ToDate
		, CASE WHEN @DiscountType = 1 THEN ISNULL(d.FromAmount, 0) ELSE 0 END AS FromAmount
		, CASE WHEN @DiscountType = 1 THEN ISNULL(d.ToAmount, 0) ELSE 0 END AS ToAmount
		, d.Rate
		, COUNT(p.ProductId) AS NumberOfProduct
		, COUNT(a.PartyID) AS NumberOfPayer
		, STUFF((
				SELECT ', ' + ISNULL(CAST(ppp.ProductName AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
					LEFT JOIN dbo.LA_f_Products3rd('') ppp ON pp.ProductId = ppp.Productid
				WHERE pp.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
		, STUFF((
				SELECT ', ' + CASE WHEN ISNULL(d.BrandName, '') = '' THEN ISNULL(CAST(pp.PartyName AS VARCHAR), '') ELSE ISNULL(CAST(d.BrandName AS VARCHAR), '') END
				FROM dbo.LA_DiscountGroupAssignment aa WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party pp WITH(NOLOCK) ON aa.PartyID = pp.PartyID
					LEFT JOIN dbo.OAS_PartyDetail d ON aa.PartyID = d.PartyID
				WHERE aa.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS PayerList
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
	WHERE h.DiscountGroupType = @DiscountType
		AND (@GroupName IS NULL OR (@GroupName IS NOT NULL AND DiscountGroupName = @GroupName))
	GROUP BY h.DiscountGroupId, h.DiscountGroupName, h.CurrencyId, h.FromDate, h.ToDate
		, CASE WHEN @DiscountType = 1 THEN ISNULL(d.FromAmount, 0) ELSE 0 END
		, CASE WHEN @DiscountType = 1 THEN ISNULL(d.ToAmount, 0) ELSE 0 END
		, d.Rate
END