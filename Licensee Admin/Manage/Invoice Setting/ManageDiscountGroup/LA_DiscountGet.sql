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
	DECLARE 
		@CalculationProductIds VARCHAR(1000), 
		@DiscountProductIds VARCHAR(1000),
		@CalculationProductList VARCHAR(4000), 
		@DiscountProductList VARCHAR(4000)

	SELECT @CalculationProductIds = COALESCE(@CalculationProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR))
		 ,@CalculationProductList = COALESCE(@CalculationProductList + ',' + p.ProductName, p.ProductName)
	FROM dbo.LA_DiscountGroupProduct d WITH(NOLOCK)
	INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
	WHERE d.DiscountGroupId = @GroupId AND d.IsCalculationProduct = 1

	SELECT @DiscountProductIds = COALESCE(@DiscountProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR))
		 ,@DiscountProductList = COALESCE(@DiscountProductList + ',' + p.ProductName, p.ProductName)
	FROM dbo.LA_DiscountGroupProduct d WITH(NOLOCK)
	INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
	WHERE d.DiscountGroupId = @GroupId AND d.IsDiscountProduct = 1

	--get discount header
	SELECT h.DiscountGroupId
		, h.DiscountGroupType
		, h.DiscountGroupName
		, c.CurrencyId
		, c.CurrencyName
		, h.FromDate
		, h.ToDate
		, @CalculationProductIds	AS CalculationProductIds
		, @DiscountProductIds		AS DiscountProductIds
		, @CalculationProductList	AS CalculationProductList
		, @DiscountProductList		AS DiscountProductList
		, h.CalculationType
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN LA_f_BaseCurrency() c ON c.CurrencyId = h.CurrencyId
	WHERE DiscountGroupId = @GroupId

	--get discount setting rates
	SELECT DiscountGroupDetailId AS DiscountDetailId
		, FromAmount
		, ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
	ORDER BY FromAmount

	--get list of licensees
	SELECT DiscountGroupId,
			p.PartyId,
			p.PartyName,
			IsApplyDiscount,
			Remark 
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = a.PartyID
	WHERE DiscountGroupId = @GroupId
END
GO