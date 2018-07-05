/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateGet]
	@GroupId INT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Get rebate group [#94282]

	 Params:

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	--get products which has assigned to group
	DECLARE @ProductIds VARCHAR(200), @PartyIds VARCHAR(4000), @Rate DECIMAL(9, 8)

	SELECT @ProductIds = COALESCE(@ProductIds + ',' + CAST(ProductId AS VARCHAR), CAST(ProductId AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	SELECT @PartyIds  = COALESCE(@PartyIds  + ',' + CAST(PartyID AS VARCHAR), CAST(PartyID AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	SELECT @Rate = Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	--get rebate header
	SELECT  DiscountGroupId AS GroupId, 
			DiscountGroupName AS GroupName, 
			CurrencyId, 
			FromDate, 
			ToDate, 
			Remark, 
			@ProductIds AS ProductIds,
			@PartyIds	AS PartyIds,
			@Rate AS Rate,
			ModifiedDate
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
END
GO