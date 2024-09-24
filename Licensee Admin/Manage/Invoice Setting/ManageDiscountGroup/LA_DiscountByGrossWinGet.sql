/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
		- 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20201003@Danny: Support USDT as base currency [RedmineID: #180313]
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
		- 20220206@Danny: Return more party detail (SuspendedDate, TerminatedDate) [RedmineID: #169160]
		- 20230731@Danny: Incorporate USDT2 currency [RedmineID: #191165]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
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
	WHERE FromParty = @RepPartyId AND ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
		AND ProductId = @ProductId AND ChargeType = 1
		AND FromDate <= @ToDate AND ToDate >= @FromDate

	-- Gerenal info
	SELECT h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, h.ModifiedDate
		,h.CurrencyId, CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END AS CurrencyName
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
		,ChargeRateAfterDiscount
	FROM dbo.LA_DiscountGroupDetail WITH (NOLOCK)
	WHERE DiscountGroupId = @GroupId
	ORDER BY FromAmount

	-- Party List
	SELECT a.DiscountGroupId, a.PartyId, p.PartyName, a.Remark, op.SuspendedDate,op.TerminatedDate
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyId
		INNER JOIN dbo.OAS_partydetail op WITH(NOLOCK) ON p.PartyId = op.PartyId
	WHERE a.DiscountGroupId = @GroupId

	-- Currency List
	DECLARE @CurrencyList TABLE (LicenseeId INT, Currency INT, CurrencyCode VARCHAR(65), CurrencyName VARCHAR(50))
	INSERT INTO @CurrencyList (LicenseeId, Currency, CurrencyCode, CurrencyName)
	SELECT LicenseeId, Currency, CurrencyCode, CurrencyName
	FROM OPENQUERY(DBCUST, 'SELECT DISTINCT lc.LicenseeId, lc.Currency ,
									CASE WHEN lc.Currency = 92 THEN ''HID'' 
										WHEN lc.Currency = 142 THEN ''USDT''
										WHEN lc.Currency IN (96,202, 206, 208, 209) THEN e.Code + '' ('' + e.currency + '')''
										ELSE e.Code END AS CurrencyCode, 
									CASE WHEN lc.Currency = 51 THEN ''VND'' 
										 WHEN lc.Currency = 142 THEN ''USDT'' 
										ELSE e.currency END AS CurrencyName
							FROM bodb_Licensee.dbo.LA_f_SelLicenseeCust(0) lc
							INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
							WHERE lc.Currency NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)')


	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM @CurrencyList c1
	INNER JOIN (
		SELECT LicenseeId, CurrencyCode
	    FROM @CurrencyList
	    GROUP BY LicenseeId, CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.LicenseeId = c2.LicenseeId AND c1.CurrencyCode = c2.CurrencyCode
	
	SELECT  pl.PartyId, cl.Currency AS CurrencyId, 
			cl.CurrencyCode CurrencyName, 
			ISNULL(c.CalculationType, 0) AS CalculationType
		
	FROM @PartyList pl
		INNER JOIN @CurrencyList cl ON pl.LicenseeId = cl.LicenseeId
		LEFT JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON pl.PartyId = c.PartyId AND cl.Currency = c.CurrencyId AND c.DiscountGroupId = @GroupId
END
GO