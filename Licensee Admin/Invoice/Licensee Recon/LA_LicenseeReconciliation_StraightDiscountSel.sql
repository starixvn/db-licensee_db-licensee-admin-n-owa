/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO
-- exec [LA_LicenseeReconciliation_StraightDiscountSel] '20190101'
ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_StraightDiscountSel]
	@ReportMonth	DATE
AS
/*	Header:
	Created: 20191007@Bruce
	Task : Get straight discount for sportbook
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191007@Bruce: Create Sp [#120220]
*/
BEGIN
	SET NOCOUNT ON

	-- get base currency
	--
	DECLARE @baseCurrencyList TABLE (CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT INTO @baseCurrencyList(CurrencyId,CurrencyName)

	SELECT CurrencyId,CurrencyName FROM OPENQUERY(DBCUST, 'EXEC CustDB.dbo.LA_BaseCurrency_Sel') 

	-- 1. Get licensees have straight discount
	--
	DECLARE @Unlimited MONEY = 10000000000000
	DECLARE @straightDiscount TABLE(Id INT, CurrencyId INT)
	DECLARE @discountSettings TABLE(PartyId INT, Rate MONEY, CurrencyId INT, LicenseeCode VARCHAR(50))

	INSERT INTO @straightDiscount(id, CurrencyId)
	SELECT h.DiscountGroupId,h.CurrencyId
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON h.DiscountGroupId=d.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId=p.DiscountGroupId
	WHERE @ReportMonth BETWEEN h.FromDate AND h.ToDate
		AND p.ProductId = 0
		AND p.CalculationType > 0 -- 0 = just calculate, no discount
		AND h.DiscountGroupType <> 2 -- rebate
	GROUP BY h.DiscountGroupId,h.CurrencyId
	HAVING COUNT(d.DiscountGroupId) = 1
		AND MIN(FromAmount) = 0
		AND MAX(ToAmount) = @Unlimited

	INSERT INTO @discountSettings (PartyId, Rate, CurrencyId, LicenseeCode)
	SELECT a.PartyId, d.Rate, s.CurrencyId,pd.LicenseeCode
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON a.DiscountGroupId=d.DiscountGroupId
	INNER JOIN @straightDiscount s ON s.Id = a.DiscountGroupId
	INNER JOIN dbo.OAS_PartyDetail pd ON pd.PartyID=a.PartyID
	WHERE a.IsApplyDiscount = 1

	-- 2. Get SB fee
	DECLARE @partyIds VARCHAR(1000) = STUFF((SELECT ',' + CAST(PartyId AS VARCHAR(5)) FROM @discountSettings FOR XML PATH('')),1,1,'')
	DECLARE @FromDate DATE = DATEADD(MONTH,DATEDIFF(MONTH,0,@ReportMonth),0)
	DECLARE @ToDate DATE = DATEADD(DAY,-1,DATEADD(MONTH,1,@FromDate))

	SELECT -b.MemberWL * ISNULL(cr.Rate, c.DI_Rate) AS AmountToCompany, c.PartyID, b.CurrencyId,b.rptDate INTO #data
	FROM bodb_licenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
	INNER JOIN dbo.LA_f_ChargeInfo(@partyIds,@FromDate,@ToDate,'SB','OA',1) c ON b.SiteId=c.LicenseeId AND b.ProductId=c.ProductId
	LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr ON cr.ChargeId = c.ChargeId AND cr.CurrencyId = b.CurrencyId
	WHERE b.rptDate BETWEEN c.Fromdate AND c.Todate
		AND b.customercategory NOT IN (27, 28)
		AND b.StatusId NOT IN (-1, 101, 102, 103)

	-- 3. Exchange
	DECLARE @result TABLE(LicenseeCode VARCHAR(50), Rate MONEY, Sportsbook MONEY)

	DELETE @baseCurrencyList WHERE CurrencyId NOT IN (SELECT s.CurrencyId FROM @straightDiscount s)
	WHILE EXISTS(SELECT TOP 1 1 FROM @baseCurrencyList)
	BEGIN
		DECLARE @CurrencyName VARCHAR(5)
		DECLARE @CurrencyId INT
		
		SELECT TOP 1 @CurrencyName=CurrencyName,@CurrencyId=CurrencyId FROM @baseCurrencyList
		DELETE @baseCurrencyList WHERE CurrencyName = @CurrencyName

		INSERT INTO @result(LicenseeCode,Rate,Sportsbook)
		SELECT s.LicenseeCode,s.Rate, SUM(d.AmountToCompany * e.BaseCurrencyRate)
		FROM #data d
		INNER JOIN @discountSettings s ON d.PartyID=s.PartyId
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CurrencyName) e ON e.ExchangeId=d.CurrencyId AND e.exchangedate=d.rptDate
		WHERE s.CurrencyId=@CurrencyId
		GROUP BY s.LicenseeCode,s.Rate
	END

	SELECT * FROM @result
	DROP TABLE #data
END
GO

