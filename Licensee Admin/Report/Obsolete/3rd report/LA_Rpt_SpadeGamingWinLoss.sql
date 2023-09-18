/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_SpadeGamingWinloss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*
 * Created by : [20200219@Mason.Nguyen]
 * Task  : Get SpadeGaming Winloss
 * Revisions
	- 20200219@Mason: Intergrate SpadeGaming [#123959]
	- 20200409@Mason: Integrate SA Gaming [#129276]
	- 20200508@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
	- 20220110@Danny: SG - Jackpot prize integration [#167089]
	- 20220407@Percy: Return LicenseeContribution & FullContribution [RedmineID: #171190]
 * Param's Explanation:
 *
 */

BEGIN
	SET NOCOUNT ON

	DECLARE  @Contribution INT = 4599,
			 @JackpotPrize INT = 4600

	DECLARE @f_date3rd DATE = @FromDate
	DECLARE @t_date3rd DATE = @ToDate
	DECLARE @f_date DATE = DATEADD(DAY, -1, @FromDate)
	DECLARE @t_date DATE = DATEADD(DAY, 1, @ToDate)

	DECLARE @SG_BettypeIdList TABLE (BetTypeId INT)
	INSERT INTO @SG_BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'SG') la

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC LA_PartyListSel
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @3rdRate
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
	FROM LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'SG', 'OA') r 
	INNER JOIN #PartyList p on p.ParentId = r.PartyID

	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	
	-- ​Pay to Supplier: equals 3.5%(0.035) of [Licensee Win Loss]
	INSERT INTO #ChargeRate
	SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SG') c
	INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
	WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	UPDATE #Exchange SET CurrencyCode = CASE WHEN ExchangeID = 51 THEN 'INH' 
											 WHEN ExchangeID = 92 THEN 'HID' END
	WHERE ExchangeID IN (51,92)
	
	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID					INT,
		PartyName				NVARCHAR(100),
		ParentId				INT,
		ParentName				NVARCHAR(100),
		Winlostdate				DATETIME,
		CurrencyId				INT,
		Turnover				MONEY,
		TotalTrans				INT,
		CustomerWinLoss			MONEY,
		LicenseeWinloss			MONEY,
		LicensingFee			MONEY,
		PayToSupplier			MONEY,
		LicenseeContribution	MONEY,
		FullContribution		MONEY,
		JackpotPrize			MONEY,
		LicenseeChargeRate		MONEY,
		IsDeposit				BIT)

	-- Calculate for desposit & credit
	
	;WITH cte_detail AS
	(
	SELECT
		b.RptDate3rd as Winlostdate,
		b.CurrencyId,
		b.SiteId,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Turnover END) AS Turnover,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.BetCount END) AS TotalTrans,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
		- SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS LicenseeWinloss,
		SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
		SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
		SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
	WHERE b.RptDate BETWEEN @f_date AND @t_date
		AND b.RptDate3rd BETWEEN @f_date3rd AND @t_date3rd
		AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
		AND b.BetTypeId IN (SELECT x.BetTypeId FROM @SG_BettypeIdList x)
	GROUP BY b.RptDate3rd, b.CurrencyId, b.SiteId
	)
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,LicenseeContribution,FullContribution,JackpotPrize,LicenseeChargeRate,IsDeposit)
	SELECT	ci.PartyID,
			b.Winlostdate,
			b.CurrencyId,
			SUM(Turnover),
			SUM(TotalTrans),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinloss),
			SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize) AS LicensingFee,
			SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier,
			SUM(LicenseeContribution),
			SUM(FullContribution),
			SUM(JackpotPrize),
			SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
			ci.IsDeposit
	FROM	cte_detail b
	INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
	LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
	GROUP BY b.Winlostdate, b.CurrencyId, ci.PartyID, ci.isDeposit
	-- End region
	
	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		LicenseeContribution	MONEY,
		FullContribution	MONEY,
		JackpotPrize	MONEY,
		LicenseeChargeRate MONEY,
		IsDeposit		BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier,LicenseeContribution,FullContribution,JackpotPrize, LicenseeChargeRate,IsDeposit)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, 
	  CASE WHEN IsDeposit = 0 THEN 0 ELSE LicenseeChargeRate   + LicenseeContribution - JackpotPrize  END   AS LicensingFee, td.PayToSupplier, td.LicenseeContribution, td.FullContribution, td.JackpotPrize, td.LicenseeChargeRate,td.IsDeposit
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	
	
	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20),
		JackpotPrize	MONEY,
		LicenseeContribution	MONEY,
		FullContribution		MONEY
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		JackpotPrize	MONEY,
		LicenseeContribution	MONEY,
		FullContribution		MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		;WITH TotalByParty AS(
			SELECT td.ParentId, td.PartyId, td.IsDeposit,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM(td.LicenseeContribution * e.BaseCurrencyRate) LicenseeContribution,
				SUM(td.FullContribution * e.BaseCurrencyRate) FullContribution,
				SUM(td.JackpotPrize * e.BaseCurrencyRate) JackpotPrize,
				SUM(td.LicenseeChargeRate * e.BaseCurrencyRate) LicenseeChargeRate
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId, td.IsDeposit
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome,JackpotPrize,LicenseeContribution,FullContribution)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN  IsDeposit = 0 THEN 0 
					 ELSE  CASE WHEN LicenseeChargeRate < 0 THEN 0 
								ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize END),
			SUM(PayToSupplier),
			SUM(CASE WHEN  IsDeposit = 0 THEN 0 
					 ELSE  CASE WHEN LicenseeChargeRate < 0 THEN 0 
								ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize END - PayToSupplier),
			SUM(JackpotPrize),
			SUM(LicenseeContribution),
			SUM(FullContribution)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome,JackpotPrize,LicenseeContribution,FullContribution)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM(LicensingFee - PayToSupplier),
			SUM(JackpotPrize),
			SUM(LicenseeContribution),
			SUM(FullContribution)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
	END
	
	-- Select data by Parties
	SELECT 
		r.PartyId,
		r.PartyName,
		r.ParentId,
		r.ParentName,
		r.WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		r.JackpotPrize AS JackpotPrizeOriginal,
		r.LicenseeContribution AS LicenseeContributionOriginal,
		r.FullContribution AS FullContributionOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
		CAST((r.JackpotPrize * e.Rate) AS MONEY) AS JackpotPrize,
		CAST((r.LicenseeContribution * e.Rate) AS MONEY) AS LicenseeContribution,
		CAST((r.FullContribution * e.Rate) AS MONEY) AS FullContribution
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT 
		PartyId,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		LicensingFee,
		PayToSupplier,
		CompanyIncome,
		JackpotPrize,
		LicenseeContribution,
		FullContribution
	FROM @Total t
	WHERE Currency = @BaseCurrencyName
	-- End Region
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
GO