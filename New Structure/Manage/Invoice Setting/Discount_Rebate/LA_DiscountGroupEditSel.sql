USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupEditSel @DiscountId INT
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
	WHERE DiscountGroupId = @DiscountId

	--get discount header
	SELECT @DiscountId AS DiscountGroupId
		, @DiscountName AS DiscountGroupName
		, @CurrencyId AS CurrencyId
		, @FromDate AS FromDate
		, @ToDate AS ToDate

	--get discount detail
	SELECT FromAmount
		, CASE WHEN ToAmount >= 10000000000000 THEN 'Unlimited' ELSE ToAmount END ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountId
	ORDER BY FromAmount

	--get products
	--++get all products
	EXEC dbo.LA_ProductListSelAll

	--get products which has assigned to group
	SELECT ProductId
	FROM dbo.LA_DiscountGroupProduct WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountId
	
	--get payers
	EXEC dbo.LA_Discount_PartyListSel @DiscountType = @DiscountType
		, @DiscountId = @DiscountId
		, @CurrencyId = @CurrencyId
		, @FromDate = @FromDate
		, @ToDate = @ToDate
		, @UserId = @UserId
		, @FunctionId = @FunctionId
END
GO