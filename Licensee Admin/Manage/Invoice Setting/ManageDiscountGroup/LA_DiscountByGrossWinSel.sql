/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinSel]
AS

/*  
	 Created: 20211101@Percy
	 DB: DBCUST.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CutOffDate DATE = '2019-01-01'

	SELECT h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, ISNULL(e.Code, '') AS CurrencyName
		,STUFF((
			SELECT ', ' + p.ProductName
			FROM dbo.LA_DiscountGroupProduct gp WITH (NOLOCK)
				INNER JOIN dbo.LA_f_Products3rd('') p ON gp.ProductId = p.ProductId
			WHERE gp.DiscountGroupId = h.DiscountGroupId
			FOR XML PATH (''))
			, 1, 2, '') AS ProductList
		,STUFF((
			SELECT ', ' + ISNULL(NULLIF(pd.BrandName, ''), p.PartyName)
			FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyId
				LEFT JOIN dbo.OAS_PartyDetail pd ON a.PartyId = pd.PartyId
			WHERE a.DiscountGroupId = h.DiscountGroupId
			FOR XML PATH (''), ROOT('str'), TYPE ).value('/str[1]','VARCHAR(MAX)') 
			, 1, 2, '') AS PayerList
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		LEFT JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
	WHERE h.DiscountGroupType = 13 -- Discount group by gross win
		AND h.FromDate >= @CutOffDate

	-- Get rate settings 
	SELECT h.DiscountGroupId, d.FromAmount, d.ToAmount, d.Rate	
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		 INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
	WHERE h.DiscountGroupType = 13 -- Discount group by gross win
		AND h.FromDate >= @CutOffDate
	ORDER BY d.DiscountGroupDetailId, d.FromAmount
END
GO