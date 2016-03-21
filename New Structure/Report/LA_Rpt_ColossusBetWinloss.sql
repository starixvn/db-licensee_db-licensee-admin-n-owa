USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_ColossusBetWinloss]
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
/*  Created: 20160310@Bruce
	Task : Support settlement for Colossus Bets
	DB: DBEXT/bodb02
	Revisions:
		- 20160310@Bruce: Create SP
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	-- Commission share & Cash in share
	BEGIN
		DECLARE @CBShare AS TABLE (
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			MinAmountEx		MONEY,
			MaxAmountEx		MONEY,
			BaseCurrencyId	SMALLINT,
			TypeId			SMALLINT
		)

		INSERT INTO @CBShare(Rate, MinAmount, MaxAmount, BaseCurrencyId, TypeId)
		SELECT ci.Rate, MinAmount, MaxAmount, BaseCurrencyId, ChargeType
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE FromParty = 1 AND ProductID = 15 AND ChargeType IN (6,7) AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
			@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
			ci.FromDate BETWEEN @FromDate AND @ToDate OR
			ci.ToDate BETWEEN @FromDate AND @ToDate
		)
		-- Product - 15: Colossus bet
		-- ChargeType: 6,7 are turnover and commission
	END

	-- Party List
	BEGIN
		DECLARE @PartyList AS TABLE (
			PartyId		INT,
			PartyName	VARCHAR(100),
			BranchName	VARCHAR(100),
			ParentId	INT
		)

		INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
		EXEC LA_PartyListSel
	END

	-- Get Winloss data
	BEGIN
		CREATE TABLE #TempData (
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
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(b.BetCount) TotalTrans,
				SUM(b.Turnover) Turnover,
				SUM(ISNULL(b.WinPrizeAmount,0)) Prize,
				SUM(ISNULL(b.CashOutAmount,0)) CashOut,
				SUM(ISNULL(b.BuyBackAmount,0)) CashInAmount
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
		INNER JOIN bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			ON	b.ProductID = 15 AND
				b.SiteID = (CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END) AND
				b.rptDate BETWEEN @FromDate AND @ToDate
		WHERE	b.CurrencyID <> 20 AND b.customercategory NOT IN (27, 28) AND
				p.PartyID IN (SELECT val FROM dbo.strSplit(@PartyIds, ','))
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
	END

	-- Result data
	BEGIN
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

	-- Convert base currency
		IF @BaseCurrencyName = ''
		BEGIN
			INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, Prize, CashOut, CashInAmount)
			SELECT p.PartyId, p.PartyName, g.PartyId, g.PartyName, td.rptDate, e.Code, td.TotalTrans, td.Turnover, td.Prize, td.CashOut, td.CashInAmount
			FROM #TempData td 
				INNER JOIN bodb02.dbo.Exchange e ON td.CurrencyId = e.ExchangeID
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		END
		ELSE
		BEGIN
			INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, Prize, CashOut, CashInAmount)
			SELECT p.PartyId, p.PartyName, g.PartyId, g.PartyName, td.rptDate, e.Code, td.TotalTrans, td.Turnover * e.BaseCurrencyRate, td.Prize * e.BaseCurrencyRate, td.CashOut * e.BaseCurrencyRate, td.CashInAmount * e.BaseCurrencyRate
			FROM #TempData td
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		END
	END

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

		-- convert min/max amount to current currency
		UPDATE s SET
			MinAmountEx = MinAmount * e.Rate,
			MaxAmountEx = MaxAmount * e.Rate
		FROM @CBShare s
		INNER JOIN #Exchange e ON s.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate

		-- calculate commission/ cash in share
		UPDATE g SET 
			Commission = g.Turnover * cm.Rate,
			CashInShare = g.CashInAmount * cs.Rate
		FROM @GrandTotal g
		INNER JOIN @CBShare cm ON cm.TypeId = 6 AND g.Turnover >= cm.MinAmountEx AND g.Turnover < cm.MaxAmountEx		 -- Commission share
		INNER JOIN @CBShare cs ON cs.TypeId = 7 AND g.CashInAmount >= cs.MinAmountEx AND g.CashInAmount < cs.MaxAmountEx -- Cash in share
		WHERE g.CurrencyName = @tempCurrency
		
		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
		DELETE FROM #Exchange
	END

	UPDATE @GrandTotal
	SET AmountDueToColossusBet = Turnover - Prize - CashOut - Commission - CashInShare
	--EndRegion Grand total data
	
	SELECT * FROM #Result
	SELECT	CurrencyName,
			ISNULL(AmountDueToColossusBet,0) AmountDueToColossusBet,
			ISNULL(TotalTrans,0) TotalTrans,
			ISNULL(Turnover,0) Turnover,
			ISNULL(Prize,0) Prize,
			ISNULL(CashOut,0) CashOut,
			ISNULL(Commission,0) Commission,
			ISNULL(CashInShare,0) CashInShare,
			ISNULL(CashInAmount,0) CashInAmount
	FROM @GrandTotal
	
	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #Exchange
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_ColossusBetWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_ColossusBetWinloss] TO bodbAdminNet