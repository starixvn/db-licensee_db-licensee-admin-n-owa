USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupInfoSel @DiscountGroupType TINYINT
	, @DiscountGroupId SMALLINT = 0
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

	SELECT @GroupName = CASE WHEN ISNULL(@GroupName, '') = '' THEN NULL ELSE @GroupName END
		, @DiscountGroupId = CASE WHEN ISNULL(@DiscountGroupId, 0) = 0 THEN NULL ELSE @DiscountGroupId END
		--, @DiscountGroupType = CASE WHEN ISNULL(@DiscountGroupType, 0) = 0 THEN NULL ELSE @DiscountGroupType END

	IF @GroupName IS NOT NULL AND @DiscountGroupType IS NOT NULL
	BEGIN
		SELECT @DiscountGroupId = DiscountGroupId
		FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
		WHERE DiscountGroupName = @GroupName AND DiscountGroupType = @DiscountGroupType
	END
	
	SELECT h.DiscountGroupId, h.DiscountGroupName, ISNULL(ex.Code, '') AS CurrencyName , h.FromDate, h.ToDate
		, CASE WHEN DiscountGroupType = 1 THEN ISNULL(d.FromAmount, 0) ELSE 0 END AS FromAmount
		, CASE WHEN DiscountGroupType = 1 THEN ISNULL(d.ToAmount, 0) ELSE 0 END AS ToAmount
		, d.Rate
		, COUNT(DISTINCT p.ProductId) AS NumberOfProduct
		, COUNT(DISTINCT a.PartyID) AS NumberOfPayer
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
				FOR XML PATH (''), ROOT('str'), TYPE 
					).value('/str[1]','VARCHAR(MAX)') 
			  , 1, 2, '') AS PayerList
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		LEFT JOIN bodb02.dbo.Exchange ex WITH(NOLOCK) ON h.CurrencyId = ex.ExchangeId
	WHERE (@DiscountGroupId IS NULL OR (@DiscountGroupId IS NOT NULL AND h.DiscountGroupId = @DiscountGroupId))
		AND DiscountGroupType = @DiscountGroupType
	GROUP BY h.DiscountGroupId, h.DiscountGroupName, ISNULL(ex.Code, ''), h.FromDate, h.ToDate
		, CASE WHEN DiscountGroupType = 1 THEN ISNULL(d.FromAmount, 0) ELSE 0 END
		, CASE WHEN DiscountGroupType = 1 THEN ISNULL(d.ToAmount, 0) ELSE 0 END
		, d.Rate
END
GO
GRANT VIEW DEFINITION ON dbo.LA_DiscountGroupInfoSel TO vnteam
GRANT EXECUTE ON dbo.LA_DiscountGroupInfoSel TO bodbAdminNet
GO