/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].LA_Rpt_LicPerformanceLicenseeAnalysis (
	@PartyIDs		VARCHAR(4000),
	@ProductCodes	VARCHAR(500),
	@FromDate		DATE,
	@ToDate			DATE,
	@BaseCurrencyId	INT = 6, -- EUR
	@Environment	VARCHAR(10) = 'PRO'
)
AS
/*
	Created: BRUCE
	Date: 20190226
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee

	Revisions:
		- 20190226@Bruce: create SP [RedmineID: #105205]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ReportDate DATE = DATEADD(month, DATEDIFF(month, 0, @FromDate), 0)
	DECLARE @tmpProducts TABLE(ProductId INT, ProductCode VARCHAR(10))
	DECLARE @BaseCurrency VARCHAR(10) = (SELECT Code FROM bodb02.dbo.Exchange WITH (NOLOCK)WHERE exchangeid = @BaseCurrencyId)

	-- Product list
	INSERT INTO @tmpProducts(ProductId,ProductCode)
	SELECT ProductId, ProductCode
	FROM dbo.LA_f_LicPerformanceAnalysisProduct()
	WHERE ProductCode IN (SELECT val FROM dbo.strSplit(@ProductCodes, ','))

	-- Charge info
	--
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, CAST(ci.DI_Rate AS DECIMAL(6,5)) AS Rate, ci.Fromdate, ci.ToDate
	INTO #tmpChargeInfo
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	-- Exchange
	--
	CREATE TABLE #tmpExchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #tmpExchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)

	CREATE NONCLUSTERED INDEX Idx_Exchange ON #tmpExchange (ExchangeDate, ExchangeID)

	-- Amount to company
	--
	CREATE TABLE #tmpAmountToCompany (
		PartyId				INT,
		ProductId			INT,
		Winloss				MONEY,
		Fee					MONEY,
		NegativeFee			MONEY,
		Minfee				MONEY,
		IsChargedByMinFee	BIT,
		Discount			MONEY,
		DiscountRate		MONEY,
		DiscountRemark		VARCHAR(1000),
		Rebate				MONEY,
		RebateRate			MONEY,
		RebateRemark		VARCHAR(1000)
	)

	INSERT INTO #tmpAmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
	EXEC dbo.LA_AmountToCompanySel
		@FromDate = @FromDate,
		@ToDate = @ToDate,
		@PartyIDs = @PartyIds,
		@ProductCodes = @ProductCodes,
		@BaseCurrency = @BaseCurrency

	-- Turnover, Betcount, Turnover no draw
	--
	;WITH cte_Data AS(
		SELECT p.PartyId,p.ProductId,
			SUM(b.BetCount)				AS BetCount,
			SUM(b.Turnover * e.Rate)	AS Turnover,
			SUM(b.Turnover * (CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END)  * e.Rate)	AS TurnoverNoDraw
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		INNER JOIN #tmpChargeInfo p ON p.LicenseeId = b.SiteId
			AND b.ProductId = p.ProductID
			AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914) -- exclude BT, CO
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY p.PartyId,p.ProductId
	)
	SELECT a.PartyId,a.ProductID,a.Discount, a.Rebate,d.Turnover,d.TurnoverNoDraw,d.BetCount,
		a.Winloss AS LicenseeWinloss,
		a.Fee AS LicensingFee,
		CAST(0 AS MONEY) AS Adjustment,
		CASE WHEN a.Rebate = 0 THEN 0 ELSE a.RebateRate END AS RebateRate
	INTO #tmpResult
	FROM #tmpAmountToCompany a
	LEFT JOIN cte_Data d ON d.PartyID = a.PartyId AND d.ProductID=a.ProductId

	-- Adjustment
	--
	DECLARE @AdjustmentId INT = (SELECT ProductId FROM @tmpProducts WHERE ProductCode = 'ADJUST')

	IF @AdjustmentId IS NOT NULL
	BEGIN
		-- invoice item type:
		--11	-	Debit for Data Fee
		--12	-	Credit for Data Fee
		--13	-	Debit for Rebate
		--14	-	Credit for Rebate
		--17	-	Software Data Fee (others)
		INSERT INTO #tmpResult(PartyId,ProductId,Adjustment)
		SELECT h.PartyId, @AdjustmentId, ISNULL(Income * e.Rate,0) - ISNULL(Expense * e.Rate,0)
		FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN #tmpExchange e ON e.ExchangeID=h.CurrencyId AND CAST(h.CreatedDateTime AS DATE) = e.ExchangeDate
		WHERE h.CreatedDateTime BETWEEN @FromDate AND @ToDate
			AND h.StatusId = 0 -- Active invoice = 0
			AND s.InvItemTypeId IN (11,12,13,14,17)
			AND h.Environment = @Environment
			AND h.PartyId IN (SELECT DISTINCT c.PartyID FROM #tmpChargeInfo c)
	END

	-- Result
	--
	SELECT @ReportDate					AS ReportDate,
		p.OldRefID						AS SiteId,
		r.ProductId,
		@BaseCurrencyId					AS CurrencyId,
		CAST(1 AS BIT)					AS IsBillingCurrency,
		ISNULL(r.Turnover,0)			AS Turnover,
		ISNULL(r.TurnoverNoDraw,0)		AS TurnoverNoDraw,
		ISNULL(r.BetCount,0)			AS BetCount,
		ISNULL(r.LicenseeWinloss,0)		AS LicenseeWinloss,
		ISNULL(r.LicensingFee,0)		AS LicensingFee,
		ISNULL(r.Discount,0)			AS Discount,
		ISNULL(r.Rebate,0)				AS Rebate,
		ISNULL(r.RebateRate,0)			AS RebateRate,
		r.Adjustment
	FROM #tmpResult r
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID=r.PartyId
	WHERE p.PartyType = 1 AND p.OldRefID IS NOT NULL

	DROP TABLE #tmpAmountToCompany
	DROP TABLE #tmpExchange
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpResult
END
GO 
