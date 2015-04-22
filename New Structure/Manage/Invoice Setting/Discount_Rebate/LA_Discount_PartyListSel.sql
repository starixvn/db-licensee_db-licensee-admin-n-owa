USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_Discount_PartyListSel @DiscountType TINYINT
	, @DiscountId SMALLINT = 0
	, @CurrencyId TINYINT = 0
	, @FromDate DATE = NULL
	, @ToDate DATE = NULL

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

	DECLARE @PartyIds TABLE (PartyId INT, DiscountId SMALLINT)

	INSERT INTO @PartyIds(PartyId, DiscountId)
		SELECT DISTINCT a.PartyId, a.DiscountGroupId
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		WHERE h.DiscountGroupType = @DiscountType
			AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND h.CurrencyId = @CurrencyId))
			AND ((@FromDate IS NULL OR (@FromDate IS NOT NULL AND @FromDate BETWEEN h.FromDate AND h.ToDate))
					OR (@ToDate IS NULL OR (@ToDate IS NOT NULL AND @ToDate BETWEEN h.FromDate AND h.ToDate))
				)

	--list of payers not in group
	SELECT p.PartyId, PartyName, BrandName--, ParentId
	FROM @PartyList p
	WHERE p.ParentId NOT IN (999) 
		AND p.PartyId NOT IN (999)
		AND p.PartyId NOT IN (SELECT PartyId FROM @PartyIds)
		
	--list of payer in group
	IF @DiscountId <> 0
	BEGIN
		SELECT p.PartyId, pp.PartyName, ppp.BrandName
		FROM @PartyIds p
			INNER JOIN dbo.OAS_Party pp WITH(NOLOCK) ON p.PartyId = pp.PartyID
			INNER JOIN dbo.OAS_PartyDetail ppp WITH(NOLOCK) ON p.PartyId = ppp.PartyID
		WHERE p.DiscountId = @DiscountId
	END

	----list of payer has been billing
	--IF @DiscountId <> 0
	--BEGIN
	--	SELECT p.PartyId
	--	FROM @PartyIds p
	--		--inner join LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
	--	WHERE p.DiscountId = @DiscountId
	--END
END
