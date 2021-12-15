/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinGet]
	@GroupId INT
AS

/*  
	 Created: 20211101@Percy
	 DB: DBLIC.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @RepPartyId INT -- Representative Party
	DECLARE @ProductId INT, @ProductName VARCHAR(100)
	DECLARE @ChargeRate MONEY = 0, @FromDate DATE, @ToDate DATE

	DECLARE @PartyList TABLE (PartyId INT, LicenseeId INT)
	INSERT INTO @PartyList (PartyId, LicenseeId)
	SELECT a.PartyId, p.OldRefId
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyId
	WHERE DiscountGroupId = @GroupId

	SELECT TOP 1 @RepPartyId = PartyId FROM @PartyList
	SELECT TOP 1 @ProductId = gp.ProductId FROM dbo.LA_DiscountGroupProduct gp WITH (NOLOCK) WHERE gp.DiscountGroupId = @GroupId
	SELECT TOP 1 @ProductName = ProductName FROM dbo.LA_f_Products3rd('') WHERE ProductId = @ProductId
	SELECT TOP 1 @FromDate = FromDate, @ToDate = ToDate FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK) WHERE DiscountGroupId = @GroupId

	SELECT @ChargeRate = Rate FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty = @RepPartyId AND ToParty IN (1, 9, 11, 98)
		AND ProductId = @ProductId AND ChargeType = 1
		AND FromDate <= @ToDate AND ToDate >= @FromDate

	-- Gerenal info
	SELECT h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, h.ModifiedDate
		,h.CurrencyId, e.Code AS CurrencyName
		,CONVERT(VARCHAR(100), @ProductId) AS CalculationProductIds
		,CONVERT(VARCHAR(100), @ProductId) AS DiscountProductIds
		,@ProductName AS CalculationProductList
		,@ProductName AS DiscountProductList
		,@ChargeRate AS ChargeRate
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
	WHERE h.DiscountGroupId = @GroupId

	-- Tier rate settings
	SELECT DiscountGroupDetailId AS DiscountDetailId, FromAmount, ToAmount, Rate
		,@ChargeRate - Rate AS ChargeRateAfterDiscount
	FROM dbo.LA_DiscountGroupDetail WITH (NOLOCK)
	WHERE DiscountGroupId = @GroupId
	ORDER BY FromAmount

	-- Party List
	SELECT a.DiscountGroupId, a.PartyId, p.PartyName, a.Remark
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyId
	WHERE a.DiscountGroupId = @GroupId

	-- Currency List
	DECLARE @CurrencyList TABLE (LicenseeId INT, Currency INT)
	INSERT INTO @CurrencyList (LicenseeId, Currency)
	SELECT LicenseeId, Currency
	FROM OPENQUERY(DBCUST, 'SELECT DISTINCT LicenseeId, Currency FROM bodb_Licensee.dbo.LA_f_SelLicenseeCust(0) WHERE Currency <> 20')
	
	SELECT pl.PartyId, cl.Currency AS CurrencyId, e.Code AS CurrencyName, ISNULL(c.CalculationType, 0) AS CalculationType
	FROM @PartyList pl
		INNER JOIN @CurrencyList cl ON pl.LicenseeId = cl.LicenseeId
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON cl.Currency = e.ExchangeId
		LEFT JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON pl.PartyId = c.PartyId AND cl.Currency = c.CurrencyId AND c.DiscountGroupId = @GroupId
END
GO