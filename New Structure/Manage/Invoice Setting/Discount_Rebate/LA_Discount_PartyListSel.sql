USE bodb_licensee
GO
ALTER PROCEDURE [dbo].[LA_Discount_PartyListSel] @DiscountGroupType TINYINT
	, @DiscountGroupId SMALLINT = 0
	, @CurrencyId TINYINT = 0
	, @FromDate DATE = NULL
	, @ToDate DATE = NULL
	, @ProductIds VARCHAR(100) = ''
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

	DECLARE @PartiesInAnyGroup TABLE (PartyId INT, DiscountId SMALLINT)
	INSERT INTO @PartiesInAnyGroup(PartyId, DiscountId)
	SELECT DISTINCT a.PartyId, a.DiscountGroupId
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId			
	WHERE h.DiscountGroupType = @DiscountGroupType
		AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND h.CurrencyId = @CurrencyId))
		AND ((@FromDate IS NULL OR (@FromDate IS NOT NULL AND @FromDate BETWEEN h.FromDate AND h.ToDate))
				OR (@ToDate IS NULL OR (@ToDate IS NOT NULL AND @ToDate BETWEEN h.FromDate AND h.ToDate))				
				OR h.FromDate BETWEEN @FromDate AND @ToDate
				OR h.ToDate BETWEEN @FromDate AND @ToDate
			)				

	--list of payers not in group
	SELECT p.PartyId, PartyName, BrandName--, ParentId
	FROM @PartyList p
	WHERE p.ParentId NOT IN (999, 0)
		AND p.PartyId NOT IN (999)
		AND p.PartyId NOT IN (SELECT PartyId FROM @PartiesInAnyGroup)		
		
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