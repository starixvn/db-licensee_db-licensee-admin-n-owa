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
		
	 Params:
		+ UserID : 
			- 0 get list Party of All user
		+ FunctionID : 
			- 0 get list Party when config in manage User	
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @CurrencyId TINYINT, @DiscountType TINYINT, @FromDate DATE, @ToDate DATE, @DiscountName VARCHAR(100)
	SELECT @DiscountType = DiscountGroupType
		, @DiscountName = DiscountGroupName
		, @CurrencyId = CurrencyId
		, @FromDate = FromDate
		, @ToDate = ToDate
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--get products which has assigned to group
	DECLARE @ProductIds VARCHAR(125)
	SET @ProductIds = NULL
	SELECT @ProductIds = COALESCE(@ProductIds + ',' + CAST(ProductId AS VARCHAR), CAST(ProductId AS VARCHAR))
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--get discount header
	SELECT @DiscountGroupId AS DiscountGroupId
		, @DiscountName AS DiscountGroupName
		, @CurrencyId AS CurrencyId
		, @FromDate AS FromDate
		, @ToDate AS ToDate
		, @ProductIds AS ProductIds

	--get discount detail
	SELECT DiscountGroupDetailId 
		, FromAmount
		--, CASE WHEN ToAmount >= 10000000000000 THEN 'Unlimited' ELSE ToAmount END ToAmount
		, ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	ORDER BY FromAmount

	
	
	----get payers
	--EXEC dbo.LA_Discount_PartyListSel @DiscountGroupType = @DiscountType
	--	, @DiscountGroupId = @DiscountGroupId
	--	, @CurrencyId = @CurrencyId
	--	, @FromDate = @FromDate
	--	, @ToDate = @ToDate
	--	, @UserId = @UserId
	--	, @FunctionId = @FunctionId
END
GO
GRANT VIEW DEFINITION ON dbo.LA_DiscountGroupEditSel TO vnteam
GRANT EXECUTE ON dbo.LA_DiscountGroupEditSel TO bodbAdminNet
GO