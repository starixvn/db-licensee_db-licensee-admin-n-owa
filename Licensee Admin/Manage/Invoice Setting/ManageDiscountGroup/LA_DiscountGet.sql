/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE LA_DiscountGet 
	@GroupId INT
AS
/*  
	 Created: 20180628@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180628@Parsons: Get discount groups info [#94282]

	 Params:

	 Explannation: EXEC LA_DiscountGet @GroupId = 0
*/
BEGIN
	SET NOCOUNT ON

	--get products which has assigned to group
	DECLARE @CalculationProductIds VARCHAR(200), @DiscountProductIds VARCHAR(200)

	SELECT @CalculationProductIds = COALESCE(@CalculationProductIds + ',' + CAST(ProductId AS VARCHAR), CAST(ProductId AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	SELECT @DiscountProductIds = COALESCE(@DiscountProductIds + ',' + CAST(ProductId AS VARCHAR), CAST(ProductId AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId AND IsDiscountProduct = 1

	--get discount header
	SELECT DiscountGroupId
		, DiscountGroupType
		, DiscountGroupName
		, CurrencyId
		, FromDate
		, ToDate
		, Remark
		, @CalculationProductIds	AS CalculationProductIds
		, @DiscountProductIds		AS DiscountProductIds
		, CalculationType
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	
	--get list of licensees
	SELECT DiscountGroupId,
			PartyID,
			IsApplyDiscount,
			Remark 
	FROM dbo.LA_DiscountGroupAssignment WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId

	--get discount setting rates
	SELECT DiscountGroupDetailId 
		, FromAmount
		, ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
	ORDER BY FromAmount
END
GO