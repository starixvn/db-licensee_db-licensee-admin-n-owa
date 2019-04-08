/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].LA_GEN_LicPerformanceAnalysis_Report (
	@FromDate		DATE,
	@ToDate			DATE,
	@ProductCodes	VARCHAR(500),
	@Environment	VARCHAR(10),
	@IsOverwrite	BIT = 0,
	@PartyIDs		VARCHAR(4000) = ''
)
AS
/*
	Created: BRUCE
	Date: 20190312
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee
	Remark: generate licensee performance analysis report

	Revisions:
		- 20190312@Bruce: create SP [RedmineID: #105205]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @OfficialPartyType SMALLINT = 1
	DECLARE @AdjustmentId INT = 9000
	DECLARE @ReportDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)

	-- Product list
	--
	DECLARE @tmpProductList TABLE(ProductId INT, ProductCode VARCHAR(10))

	INSERT INTO @tmpProductList(ProductId,ProductCode)
	SELECT ProductId, ProductCode
	FROM dbo.LA_f_LicPerformanceAnalysisProduct()
	WHERE ProductCode IN (SELECT val FROM dbo.strSplit(@ProductCodes, ','))

	-- Party List
	--	
	DECLARE @tmpPartyList AS TABLE(PartyId INT,SiteId INT, BaseCurrencyId INT)

	INSERT INTO @tmpPartyList(PartyId,SiteId,BaseCurrencyId)
	SELECT p.PartyID,p.OldRefID,d.BaseCurrencyId
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
	WHERE PartyType = @OfficialPartyType AND OldRefID IS NOT NULL AND ISNULL(d.IsDeposit,0) = 1

	IF (@PartyIDs = '')
	BEGIN
		SET @PartyIDs = (SELECT CAST(PartyID AS VARCHAR(5)) + ',' FROM @tmpPartyList FOR XML PATH(''))
		SET @PartyIDs = LEFT(@PartyIDs, LEN(@PartyIDs) - 1)
	END

	-- Generate adjustment values
	--
	IF EXISTS(SELECT * FROM @tmpProductList WHERE ProductId = @AdjustmentId)
	EXEC dbo.LA_GEN_LicPerformanceAnalysis_Adjustment 
		@PartyIds = @PartyIDs, 
		@ReportDate = @ReportDate,
		@Environment = @Environment,
		@IsOverwrite = @IsOverwrite

	-- Charge info
	--
	SELECT DISTINCT LicenseeID,ProductID, Fromdate, ToDate, PartyId
	INTO #tmpPartyChargeRates
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	WHERE DI_Rate > 0

	CREATE INDEX IX_tmpPartyChargeRates ON #tmpPartyChargeRates(LicenseeID, ProductID)

	-- re-filter party & product by overwrite flag
	--
	IF @IsOverwrite = 0
	BEGIN
		DECLARE @skip TABLE(SiteID INT, ProductId INT)
		;WITH a AS(
			SELECT DISTINCT SiteId, ProductId
			FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis WITH(NOLOCK)
			WHERE ReportDate = @ReportDate AND ProductId <> @AdjustmentId AND IsBillingCurrency = 1
		),b AS(
			SELECT DISTINCT LicenseeId, ProductId FROM #tmpPartyChargeRates
		)
		INSERT INTO @skip(SiteID,ProductId)
		SELECT b.LicenseeID,b.ProductId
		FROM b LEFT JOIN a ON a.ProductId = b.ProductId AND a.SiteId=b.LicenseeID
		WHERE a.SiteId IS NOT NULL

		DELETE a FROM #tmpPartyChargeRates a INNER JOIN @skip s ON a.ProductId = s.ProductId AND a.LicenseeID=s.SiteId
	END

	DELETE b FROM @tmpPartyList b WHERE b.PartyId NOT IN (SELECT a.PartyId FROM #tmpPartyChargeRates a)

	SET @PartyIDs = (SELECT CAST(PartyID AS VARCHAR(5)) + ',' FROM @tmpPartyList FOR XML PATH(''))
	SET @PartyIDs = LEFT(@PartyIDs, LEN(@PartyIDs) - 1)

	-- Turnover, Betcount, Turnover no draw
	--
	SELECT b.SiteId, b.rptDate,b.CurrencyId, b.ProductId,
		SUM(-b.MemberWL) AS Winloss, -- not support GD tip yet
		SUM(b.BetCount) AS BetCount,
		SUM(b.Turnover) AS Turnover,
		SUM(b.Turnover * (CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END)) AS TurnoverNoDraw
	INTO #tmpPerfData
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN #tmpPartyChargeRates p ON b.SiteID = p.LicenseeID AND b.ProductId = p.ProductID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.customercategory NOT IN (27, 28)
		AND b.Bettype NOT IN (901,902,903,904,911,912,913,914) -- exclude BT, CO
		AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
	GROUP BY b.SiteId,b.rptDate,b.CurrencyId, b.ProductId

	CREATE INDEX IX_tmpPerfData ON #tmpPerfData(rptDate, CurrencyId)

	-- Base currency list
	--
	DECLARE @tmpBaseCurrencyList TABLE(CurrencyId INT, Code VARCHAR(10))
	INSERT INTO @tmpBaseCurrencyList(CurrencyId,Code)
	EXEC dbo.LA_SelBaseCurrency

	-- Amount to company
	--
	CREATE TABLE #tmpPerfResult(
		PartyId				INT,
		ProductId			INT,
		Fee					MONEY,
		Discount			MONEY,
		Rebate				MONEY,
		IsChargedByMinFee	BIT,
		Winloss				MONEY,
		Turnover			MONEY,
		TurnoverNoDraw		MONEY,
		BetCount			INT,
		CurrencyId			INT
	)

	CREATE INDEX IX_tmpPerfResult ON #tmpPerfResult(PartyId, ProductID)

	DECLARE @tmpCurrency INT = 0
	DECLARE @tmpCurrencyCode VARCHAR(10)

	WHILE EXISTS (SELECT TOP 1 * FROM @tmpBaseCurrencyList)
	BEGIN
		SELECT TOP 1 @tmpCurrencyCode = Code, @tmpCurrency = CurrencyId FROM @tmpBaseCurrencyList
		DELETE @tmpBaseCurrencyList WHERE CurrencyId = @tmpCurrency

		INSERT INTO #tmpPerfResult(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee)
		EXEC dbo.[LA_AmountToCompanyByDiscountCurrencySel]
			@FromDate = @FromDate,
			@ToDate = @ToDate,
			@PartyIDs = @PartyIDs,
			@ProductCodes = @ProductCodes,
			@BaseCurrencyName = @tmpCurrencyCode,
			@BaseCurrencyId = @tmpCurrency,
			@CurrencyId = 0

		;WITH cte_Data AS(
			SELECT b.SiteID,b.ProductId,
				SUM(b.BetCount) AS BetCount,
				SUM(b.Winloss * e.BaseCurrencyRate) AS Winloss,
				SUM(b.Turnover * e.BaseCurrencyRate) AS Turnover,
				SUM(b.TurnoverNoDraw * e.BaseCurrencyRate) AS TurnoverNoDraw
			FROM #tmpPerfData b
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate,@ToDate, @tmpCurrencyCode) e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			GROUP BY b.SiteID,b.ProductId
		)
		UPDATE a SET
			Winloss = d.Winloss,
			Turnover = d.Turnover,
			TurnoverNoDraw = d.TurnoverNoDraw,
			BetCount = d.BetCount
		FROM #tmpPerfResult a
		INNER JOIN @tmpPartyList p ON a.PartyId=p.PartyId
		INNER JOIN cte_Data d ON d.ProductID=a.ProductId AND d.SiteID=p.SiteId
		WHERE a.CurrencyId IS NULL

		UPDATE #tmpPerfResult SET CurrencyId = @tmpCurrency WHERE CurrencyId IS NULL
	END

	DELETE a FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis a
	INNER JOIN @tmpPartyList p ON a.SiteId=p.SiteId
	INNER JOIN #tmpPerfResult b ON b.PartyId=p.PartyId AND a.ProductId = b.ProductId AND a.ReportDate = @ReportDate AND a.CurrencyId = b.CurrencyId

	INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis(ReportDate,SiteId,ProductId,CurrencyId,IsBillingCurrency,BetCount,Turnover,TurnoverNoDraw,LicenseeWinloss,LicensingFee,Discount,Rebate,Adjustment)
	SELECT @ReportDate,p.SiteId,a.ProductId,a.CurrencyId,
		CASE WHEN a.CurrencyId = p.BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency,
		ISNULL(a.BetCount,0)		AS BetCount,
		ISNULL(a.Turnover,0)		AS Turnover,
		ISNULL(a.TurnoverNoDraw,0)	AS TurnoverNoDraw,
		ISNULL(a.Winloss,0)			AS Winloss,
		a.Fee,
		a.Discount,
		a.Rebate,
		0
	FROM #tmpPerfResult a
	INNER JOIN @tmpPartyList p ON a.PartyId=p.PartyId

	DROP TABLE #tmpPartyChargeRates
	DROP TABLE #tmpPerfResult
	DROP TABLE #tmpPerfData
END
GO 
