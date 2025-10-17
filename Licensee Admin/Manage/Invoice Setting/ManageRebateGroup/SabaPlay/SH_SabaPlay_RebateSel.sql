/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_RebateSel]
AS
/*  
	 Created: 20251017@Danny [#241642]
	 Task :  Manage Rebate On winloss group (SabaPlay)
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20251017@Danny: select rebate groups info [#241642]

*/
BEGIN
	SET NOCOUNT ON
	
	SELECT h.DiscountGroupId AS GroupId,
			h.DiscountGroupName AS GroupName,
			h.FromDate,
			h.ToDate,
			d.Rate,
			h.DiscountGroupType AS RebateGroupType,
			COUNT(DISTINCT p.ProductId) AS NumberOfProduct,
			COUNT(DISTINCT a.PartyID) AS NumberOfPayer, 
			STUFF((
				SELECT ', ' + ISNULL(CAST(ppp.ProductName AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
					LEFT JOIN bodb_licenseeReport.dbo.SabaPlay_Products ppp WITH (NOLOCK)  ON pp.ProductId = ppp.Productid
				WHERE pp.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList, 
			 STUFF((
				SELECT ', ' + CASE WHEN ISNULL(d.BrandName, '') = '' THEN ISNULL(CAST(pp.PartyName AS VARCHAR), '') ELSE ISNULL(CAST(d.BrandName AS VARCHAR), '') END
				FROM dbo.LA_DiscountGroupAssignment aa WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party pp WITH(NOLOCK) ON aa.PartyID = pp.PartyID
					LEFT JOIN dbo.OAS_PartyDetail d ON aa.PartyID = d.PartyID
				WHERE aa.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''), ROOT('str'), TYPE 
					).value('/str[1]','VARCHAR(MAX)') 
			  , 1, 2, '') AS PartyList
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
	WHERE h.DiscountGroupType = 52 -- Rebate
	GROUP BY h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, d.Rate, h.DiscountGroupType
END
GO