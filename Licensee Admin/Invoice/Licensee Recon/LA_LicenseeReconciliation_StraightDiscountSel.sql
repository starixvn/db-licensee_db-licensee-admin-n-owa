/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_StraightDiscountSel]
	@ReportMonth	DATE
AS
/*	Header:
	Created: 20191007@Bruce
	Task : Get straight discount for sportbook
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191007@Bruce: Create Sp [#120220]
		- 20200117@Mason: Setup billing terms by Currency  [#120005]
		- 20200512@Parsons: Special handling for INH market [#128570]
		- 20201209@Parsons: Licensee Reconciliation - Change Discount column if licensee has straight rebate [#146328]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
		- 20210407@Percy: Support duo base currency - Change code for Collection Summary [RedmineID: #152089]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]

	Example:
		USE bodb_licensee
		GO

		EXEC [LA_LicenseeReconciliation_StraightDiscountSel] '20190101'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth), 0)
	DECLARE @ToDate DATE = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FromDate))

	-- Get licensees have SB straight discount
	DECLARE @DiscountSetting TABLE (PartyId INT, BaseCurrencyId INT, BaseCurrencyName VARCHAR(5), LicenseeCode VARCHAR(50), DiscountRate MONEY)
	INSERT INTO @DiscountSetting (PartyId, DiscountRate)
	SELECT a.PartyId, d.Rate
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId AND d.FromAmount = 0 AND d.ToAmount = 10000000000000 -- straight discount
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId AND p.ProductId = 0 -- SB
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId AND a.IsApplyDiscount = 1
	WHERE @ToDate BETWEEN h.FromDate AND h.ToDate
		AND h.DiscountGroupType <> 2 -- 2 = rebate, <> 2 = discount
		AND p.CalculationType IN (1, 10) -- 0 = calculated only, 1 = discount only, 10 = calculated & discount

	UPDATE d
	SET d.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6), d.BaseCurrencyName = ISNULL(e.Code, 'EUR'), d.LicenseeCode = ISNULL(UPPER(bc.LicenseeCode), '') + '|' + CONVERT(VARCHAR(50), d.PartyId)
	FROM @DiscountSetting d
		LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON d.PartyId = bc.PartyId
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
	WHERE @ToDate BETWEEN bc.FromDate AND bc.ToDate

	-- Get SB fee
	DECLARE @PartyIds VARCHAR(MAX)
	SELECT  @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(15), PartyId) FROM @DiscountSetting

	CREATE TABLE #tmpData (rptDate DATE, PartyId INT, CurrencyId INT, LicensingFee MONEY, OddsSpreadCost MONEY)

	INSERT INTO #tmpData (rptDate, PartyId, CurrencyId, LicensingFee, OddsSpreadCost)
	SELECT b.rptDate, c.PartyId, b.CurrencyId, SUM(b.LicenseeWL * ISNULL(cr.Rate, c.DI_Rate)) AS LicensingFee, SUM(b.OddsSpreadCost) AS OddsSpreadCost
	FROM (
		SELECT rptDate, SiteId, ProductId, CurrencyId
			,CONVERT(MONEY, SUM(CASE WHEN Bettype = 999 THEN 0 ELSE -MemberWL END)) AS LicenseeWL
			,CONVERT(MONEY, SUM(CASE WHEN Bettype = 999 THEN -GrossWL ELSE 0 END)) AS OddsSpreadCost
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
		WHERE rptDate BETWEEN @FromDate AND @ToDate
			AND ProductId = 0
			AND CustomerCategory NOT IN (27, 28)
			AND StatusId IN (111, 112, 113, 114, 115)
		GROUP BY rptDate, SiteId, ProductId, CurrencyId
	) b
		INNER JOIN dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1) c ON b.SiteId = c.LicenseeId AND b.ProductId = c.ProductId
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = c.ChargeId AND cr.CurrencyId = b.CurrencyId
	GROUP BY b.rptDate, c.PartyId, b.CurrencyId

	-- Base Exchange Rate
	DECLARE @BaseCurrencyList TABLE (ExchangeId INT, ExchangeName VARCHAR(5))
	INSERT INTO @BaseCurrencyList (ExchangeId, ExchangeName)
	SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @DiscountSetting

	DECLARE @ExchangeId INT, @ExchangeName VARCHAR(5)

	CREATE TABLE #Result (LicenseeCode VARCHAR(50), Rate MONEY, Sportsbook MONEY)

	WHILE EXISTS (SELECT 1 FROM @BaseCurrencyList)
	BEGIN
		SELECT TOP 1 @ExchangeId = ExchangeId, @ExchangeName = ExchangeName FROM @BaseCurrencyList

		INSERT INTO #Result (LicenseeCode, Rate, Sportsbook)
		SELECT ds.LicenseeCode, ds.DiscountRate
			,SUM(d.LicensingFee * e.BaseCurrencyRate) + CASE WHEN SUM(d.OddsSpreadCost * e.BaseCurrencyRate) < 0 THEN 0 ELSE SUM(d.OddsSpreadCost * e.BaseCurrencyRate) END
		FROM #tmpData d
			INNER JOIN @DiscountSetting ds ON ds.PartyId = d.PartyId
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @ExchangeName) e ON e.ExchangeId = d.CurrencyId AND e.ExchangeDate = d.rptDate
		WHERE ds.BaseCurrencyId = @ExchangeId
		GROUP BY ds.LicenseeCode, ds.DiscountRate

		DELETE @BaseCurrencyList WHERE ExchangeId = @ExchangeId
	END

	-- Return data
	SELECT LicenseeCode, Rate, Sportsbook
	FROM #Result

	DROP TABLE #Result
	DROP TABLE #tmpData
END
GO