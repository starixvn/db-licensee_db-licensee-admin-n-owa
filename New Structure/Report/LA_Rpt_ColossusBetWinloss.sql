--USE [bodb_licensee]
--GO

--SET ANSI_NULLS ON
--GO
--SET QUOTED_IDENTIFIER ON
--GO

declare--ALTER PROCEDURE [dbo].[LA_Rpt_ColossusBetWinloss]
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
select @partyids='30',@FromDate='20150101',@ToDate='20150131',@BaseCurrencyName='' --WITH RECOMPILE
--AS
/*  Created: 20160310@Bruce
	Task : Support settlement for Colossus Bets
	DB: DBEXT/bodb02
	Revisions:
		- 20160310@Bruce: Create SP
	Param's Explanation:
*/
--BEGIN
--	SET NOCOUNT ON

	-- Region: Charge Info
	CREATE TABLE #PartyChargeInfo (
		PartyId			INT,
		LicenseeId		INT,
		ProductID		INT,
		Rate			MONEY,
		FromDate		SMALLDATETIME,
		ToDate			SMALLDATETIME,
		ChargeType		SMALLINT,
		MinAmount		MONEY,
		MaxAmount		MONEY,
		BaseCurrencyId	SMALLINT,
		MinAmountEx		MONEY,
		MaxAmountEx		MONEY
	)
	
	INSERT INTO #PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, ChargeType, MinAmount, MaxAmount, BaseCurrencyId)
	(
		SELECT	 pa.PartyID
				,CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN pa.OldRefID ELSE lb.LabelID END
				,ci.ProductID
				,ci.Rate
				,CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END
				,CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
				,ci.ChargeType
				,ci.MinAmount
				,ci.MaxAmount
				,ci.BaseCurrencyId
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping sm WITH(NOLOCK) ON sm.ChargeID = ci.ChargeID AND sm.SystemID = 2
			INNER JOIN dbo.OAS_Party pa WITH(NOLOCK) ON pa.PartyID = ci.FromParty
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = pa.PartyID
			LEFT JOIN dbo.Labels lb WITH(NOLOCK) ON lb.LicenseeID = pa.OldRefID
		WHERE ci.FromParty IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
			AND ci.ChargeType IN (6,7)	-- 6 : Turnover, 7: Commission
			AND ci.ProductID = 15		-- 15: Colossus bet
			AND (
				@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
				@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
				ci.FromDate BETWEEN @FromDate AND @ToDate OR
				ci.ToDate BETWEEN @FromDate AND @ToDate
			)
	)
	---- End region

	-- Region: Party List
	DECLARE @PartyList AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		BranchName	VARCHAR(100),
		ParentId	INT
	)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel
	---- Endregion

	-- Region: Get exchange rate info
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region

	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
		LicenseeId		INT,
		PartyId			INT,
		rptDate			DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		Prize			MONEY,
		CashOut			MONEY,
		CashInAmount	MONEY
	)
	
	INSERT INTO #TempData (LicenseeId, PartyId, rptDate, CurrencyId, TotalTrans, Turnover, Prize, CashOut, CashInAmount)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.BetCount, 0)) TotalTrans,
				SUM(ISNULL(b.Turnover, 0)) Turnover,
				SUM(CASE WHEN b.StatusId = 113 OR b.Bettype = 18002 THEN 0 ELSE b.MemberWL END) Prize, -- exclude lose & cashout
				SUM(CASE WHEN b.Bettype = 18002 THEN b.MemberWL ELSE 0 END) CashOut,
				SUM(CASE WHEN b.Bettype = 18002 THEN b.BuyBackAmount ELSE 0 END) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #PartyChargeInfo p ON b.ProductID = p.ProductID AND b.SiteID = p.LicenseeId AND p.ChargeType = 6 -- There are two charge type: (6,7) we need only one of them to avoid duplicate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
	)	
	---- EndRegion

	-- Region: Result data
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		Prize			MONEY,
		CashOut			MONEY,
		CashInAmount	MONEY
	)

	IF @BaseCurrencyName = ''
	BEGIN
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, Prize, CashOut, CashInAmount)
		(
			SELECT p.PartyId, p.PartyName, g.PartyId, g.PartyName, td.rptDate, e.Code, td.TotalTrans, td.Turnover, td.Prize, td.CashOut, td.CashInAmount
			FROM #TempData td 
				INNER JOIN (SELECT DISTINCT ExchangeID, Code FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)) e ON td.CurrencyId = e.ExchangeID
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		)
	END
	--ELSE
	--BEGIN
	
	--	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, CommissionShare, AmountDueLicensee)
	--	SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover*e.Rate, td.MemberWL*e.Rate, td.WLShare*e.Rate, td.LicComm*e.Rate, td.CommShare*e.Rate, td.AmtLicensee*e.Rate
	--	FROM #TempData td 
	--		INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
	--		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
	--		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
	--END

	-- Region: Grand total data
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal AS TABLE(
		CurrencyName			VARCHAR(3),
		TotalTrans				INT,
		Turnover				MONEY,
		Prize					MONEY,
		CashOut					MONEY,
		CashInAmount			MONEY,
		Commission				MONEY,
		CashInShare				MONEY,
		AmountDueToColossusBet	MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		DELETE FROM #Exchange
		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,Prize,CashOut,CashInAmount)
		SELECT	@tempCurrency,
				SUM(td.TotalTrans),
				SUM(td.Turnover*e.Rate),
				SUM(td.Prize*e.Rate),
				SUM(td.CashOut*e.Rate),
				SUM(td.CashInAmount*e.Rate)
		FROM #TempData td
		INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate

		UPDATE p SET
			MinAmountEx = MinAmount * e.Rate,
			MaxAmountEx = MaxAmount * e.Rate
		FROM #PartyChargeInfo p
		INNER JOIN #Exchange e ON p.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @FromDate

		SELECT *
		FROM @GrandTotal g
		INNER JOIN #PartyChargeInfo p ON p.ChargeType = 6
		
		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END

	--UPDATE #GrandTotal
	--SET AmountDueMuayThai = WinLossShare + CommissionShare

	--UPDATE #GrandTotal
	--SET AmountDueCompany = AmountDueLicensee - AmountDueMuayThai
	----EndRegion
	
	--SELECT * FROM #Result
	--SELECT * FROM #GrandTotal
	
	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #PartyChargeInfo
	--DROP TABLE #GrandTotal
--END
--GO
--GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO [vnteam] 
--GRANT EXECUTE ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO bodbAdminNet 