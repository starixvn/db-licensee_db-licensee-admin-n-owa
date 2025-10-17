/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE [dbo].[SH_SabaPlay_RebateGet]
	@GroupId INT
AS
/*  
	 Created: 20251017@Danny [#241642]
	 Task : Manage Rebate On winloss group (SabaPlay)
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20251017@Danny: Get rebate groups info [#241642]


	 Params:

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductIds VARCHAR(200), @ProductList VARCHAR(4000), @PartyIds VARCHAR(200), @PartyList VARCHAR(4000), @Rate DECIMAL(9, 8),
	@CurrencyIds		VARCHAR(4000)

	SELECT @ProductIds = COALESCE(@ProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR)),
		@ProductList = COALESCE(@ProductList + ',' + CAST(ProductName AS VARCHAR), CAST(ProductName AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct d WITH(NOLOCK)
	INNER JOIN bodb_licenseeReport.dbo.SabaPlay_Products p  WITH(NOLOCK) ON p.ProductID = d.ProductId
	WHERE DiscountGroupId = @GroupId

	SELECT @PartyIds  = COALESCE(@PartyIds  + ',' + CAST(p.PartyID AS VARCHAR), CAST(p.PartyID AS VARCHAR)),
		@PartyList  = COALESCE(@PartyList  + ',' + CAST(PartyName AS VARCHAR), CAST(PartyName AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyId = p.PartyID
	WHERE DiscountGroupId = @GroupId
	ORDER BY PartyName ASC

	SELECT @Rate = Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId


	SELECT @CurrencyIds = COALESCE(@CurrencyIds + ',' + CAST(p.CurrencyId AS VARCHAR), CAST(p.CurrencyId AS VARCHAR))
	FROM dbo.LA_DiscountGroupCurrency p WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	--get rebate header
	SELECT  DiscountGroupId		AS GroupId,
			DiscountGroupName	AS GroupName,
			CurrencyId,
			FromDate,
			ToDate,
			DiscountGroupType	AS RebateGroupType,
			Remark,
			@ProductIds		AS ProductIds,
			@PartyIds		AS PartyIds,
			@ProductList	AS ProductList,
			@PartyList		AS PartyList,
			@Rate			AS Rate,
			ModifiedDate,
			@CurrencyIds	AS CurrencyIds
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
END
GO