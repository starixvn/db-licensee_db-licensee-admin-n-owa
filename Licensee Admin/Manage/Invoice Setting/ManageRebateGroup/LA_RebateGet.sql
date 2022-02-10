/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateGet]
	@GroupId INT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Get rebate group [#94282]
		- 20220210@Percy: Return RebateGroupType [RedmineID: #163495]

	 Params:

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductIds VARCHAR(200), @ProductList VARCHAR(4000), @PartyIds VARCHAR(200), @PartyList VARCHAR(4000), @Rate DECIMAL(9, 8)

	SELECT @ProductIds = COALESCE(@ProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR)),
		@ProductList = COALESCE(@ProductList + ',' + CAST(ProductName AS VARCHAR), CAST(ProductName AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct d WITH(NOLOCK)
	INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
	WHERE DiscountGroupId = @GroupId

	SELECT @PartyIds  = COALESCE(@PartyIds  + ',' + CAST(p.PartyID AS VARCHAR), CAST(p.PartyID AS VARCHAR)),
		@PartyList  = COALESCE(@PartyList  + ',' + CAST(PartyName AS VARCHAR), CAST(PartyName AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyId = p.PartyID
	WHERE DiscountGroupId = @GroupId
	ORDER BY PartyName

	SELECT @Rate = Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
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
			ModifiedDate
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
END
GO