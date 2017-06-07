USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupEditSel @DiscountGroupId INT
	, @UserId INT = 0
	, @FunctionId INT = 0
AS
/*  
	 Created: 20150422@Patrick
	 Task : Get discount info, products, payers to edit
	 DB: DB052.bodb_Licensee
	 Revisions:     
		+ 20170518@Bruce: Include Remark [#76133]
	 Params:
		+ UserID : 
			- 0 get list Party of All user
		+ FunctionID : 
			- 0 get list Party when config in manage User	
*/
BEGIN
	SET NOCOUNT ON

	--get products which has assigned to group
	DECLARE @ProductIds VARCHAR(125)
	SELECT @ProductIds = COALESCE(@ProductIds + ',' + CAST(ProductId AS VARCHAR), CAST(ProductId AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--get discount header
	SELECT DiscountGroupId
		, DiscountGroupType
		, DiscountGroupName
		, CurrencyId
		, FromDate
		, ToDate
		, Remark
		, @ProductIds AS ProductIds
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--get discount detail
	SELECT DiscountGroupDetailId 
		, FromAmount
		, ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	ORDER BY FromAmount
END
GO
GRANT VIEW DEFINITION ON dbo.LA_DiscountGroupEditSel TO vnteam
GRANT EXECUTE ON dbo.LA_DiscountGroupEditSel TO bodbAdminNet
GO