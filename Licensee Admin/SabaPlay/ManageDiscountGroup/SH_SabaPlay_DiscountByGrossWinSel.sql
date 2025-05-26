/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_DiscountByGrossWinSel]
	@DiscountGroupId SMALLINT = 0
AS

/*  
	Created: 20250513@Eddie
	DB: DBLIC.bodb_licensee
	Task: SabaPlay - Manage Discount Group for SabaPlay - Grid of data
	 
	Revisions:
		- 20250513@Eddie: Initialize SP [RedmineID: #220534]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT h.DiscountGroupId
		 , h.DiscountGroupName
		 , h.FromDate
		 , h.ToDate
		 , d.Rate
		 , h.DiscountGroupType
		 , ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END, '') AS CurrencyName
		 , COUNT(DISTINCT p.ProductId) AS NumberOfProduct
		 , COUNT(DISTINCT a.PartyID) AS NumberOfPayer 
		 , STUFF((
				SELECT ', ' + ISNULL(CAST(sp.ProductName AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
					LEFT JOIN bodb_licenseeReport.dbo.SabaPlay_Products sp WITH (NOLOCK) ON sp.ProductId = pp.Productid
				WHERE pp.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
		 , STUFF((
				SELECT ', ' + ISNULL(CAST(pp.ProductId AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupProduct pp WITH (NOLOCK)
					LEFT JOIN bodb_licenseeReport.dbo.SabaPlay_Products sp WITH (NOLOCK) ON sp.ProductId = pp.Productid
				WHERE pp.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductIds
		 , STUFF((
				SELECT ', ' + CASE WHEN ISNULL(d.BrandName, '') = '' THEN ISNULL(CAST(pp.PartyName AS VARCHAR), '') ELSE ISNULL(CAST(d.BrandName AS VARCHAR), '') END
				FROM dbo.LA_DiscountGroupAssignment aa WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party pp WITH(NOLOCK) ON aa.PartyID = pp.PartyID
					LEFT JOIN dbo.OAS_PartyDetail d ON aa.PartyID = d.PartyID
				WHERE aa.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''), ROOT('str'), TYPE 
					).value('/str[1]','VARCHAR(MAX)') 
			  , 1, 2, '') AS PartyList
		 , STUFF((
				SELECT ', ' + ISNULL(CAST(pp.PartyID AS VARCHAR), '')
				FROM dbo.LA_DiscountGroupAssignment aa WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party pp WITH(NOLOCK) ON aa.PartyID = pp.PartyID
				WHERE aa.DiscountGroupId = h.DiscountGroupId
				FOR XML PATH (''), ROOT('str'), TYPE 
					).value('/str[1]','VARCHAR(MAX)') 
			  , 1, 2, '') AS PartyIds
		  , h.ModifiedDate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		LEFT JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		LEFT JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
	WHERE h.DiscountGroupType = 23 -- Discount Group for SabaPlay
	  AND ( h.DiscountGroupId = @DiscountGroupId
			OR ISNULL(@DiscountGroupId, 0) = 0
		)
	GROUP BY h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, d.Rate, h.DiscountGroupType
			,ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END, ''), h.ModifiedDate
END
GO