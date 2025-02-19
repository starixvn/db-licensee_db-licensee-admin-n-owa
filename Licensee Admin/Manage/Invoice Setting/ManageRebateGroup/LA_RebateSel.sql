/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateSel]
AS
/*  
	 Created: 20180525@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180525@Parsons: Get rebate groups info [#94282]
		- 20220210@Percy: Return RebateGroupType [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
		- 20240613@Danny: Rebate on specific currencies [#FeatureID 206143]
		- 20250102@Danny: Rebate on Licensing winloss for specific currencies [RedmineID: #214767]
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
					LEFT JOIN dbo.LA_f_Products3rd('') ppp ON pp.ProductId = ppp.Productid
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
			  , 1, 2, '') AS PartyList,
			 STUFF((
				SELECT ', ' + ISNULL(CAST(pp.CurrencyId AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupCurrency pp WITH (NOLOCK)
				WHERE pp.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS CurrencyList
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
	WHERE h.DiscountGroupType IN (2, 12, 22, 32, 42) -- Rebate
	GROUP BY h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, d.Rate, h.DiscountGroupType
END
GO