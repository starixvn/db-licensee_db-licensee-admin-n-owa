USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_Discount_PartyListSel @DiscountGroupType TINYINT
	, @DiscountGroupId SMALLINT = 0
	, @CurrencyId TINYINT = 0
	, @FromDate DATE = NULL
	, @ToDate DATE = NULL
	, @ProductIds VARCHAR(125) = ''

	, @UserId INT = 0
	, @FunctionId INT = 0
AS
/*  
	 Created: 20150422@Patrick
	 Task : Get list payer list
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
	IF @CurrencyId IS NULL
		SET @CurrencyId = 0

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	
	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId = @FunctionId

	DECLARE @Products TABLE (ProductId TINYINT)
	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductIds, ',')

	DECLARE @HasProductId BIT
	IF EXISTS (SELECT TOP 1 1 FROM @Products)
		SET @HasProductId = 1

	DECLARE @PartiesInAnyGroup TABLE (PartyId INT, DiscountId SMALLINT, ProductId TINYINT)
	INSERT INTO @PartiesInAnyGroup(PartyId, DiscountId, ProductId)
		SELECT DISTINCT a.PartyId, a.DiscountGroupId, p.ProductId
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
		WHERE h.DiscountGroupType = @DiscountGroupType
			AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND h.CurrencyId = @CurrencyId))
			AND ((@FromDate IS NULL OR (@FromDate IS NOT NULL AND @FromDate BETWEEN h.FromDate AND h.ToDate))
					OR (@ToDate IS NULL OR (@ToDate IS NOT NULL AND @ToDate BETWEEN h.FromDate AND h.ToDate))
				)
			--AND (@HasProductId = 0 OR (@HasProductId <> 0 AND p.ProductId IN (SELECT ProductId FROM @Products)))

	--list of payers not in group
	SELECT p.PartyId, PartyName, BrandName--, ParentId
	FROM @PartyList p
	WHERE p.ParentId NOT IN (999, 0)
		AND p.PartyId NOT IN (999)
		AND p.PartyId NOT IN (SELECT PartyId FROM @PartiesInAnyGroup p
												INNER JOIN @Products pp ON p.ProductId = pp.ProductId)
		--AND (@HasProductId = 0 OR (@HasProductId <> 0 AND p.ProductId NOT IN (SELECT ProductId FROM @Products)))
		
	--list of payer in group
	IF @DiscountGroupId <> 0
	BEGIN
		SELECT a.PartyId, pp.PartyName, ppp.BrandName
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.OAS_Party pp WITH(NOLOCK) ON a.PartyId = pp.PartyID
			INNER JOIN dbo.OAS_PartyDetail ppp WITH(NOLOCK) ON a.PartyId = ppp.PartyID
		WHERE h.DiscountGroupId = @DiscountGroupId
	END
END
GO
GRANT VIEW DEFINITION ON dbo.LA_Discount_PartyListSel TO vnteam
GRANT EXECUTE ON dbo.LA_Discount_PartyListSel TO bodbAdminNet
GO