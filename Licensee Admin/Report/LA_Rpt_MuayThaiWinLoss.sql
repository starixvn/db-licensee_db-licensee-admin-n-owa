USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MuayThaiWinLoss]
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @TicketType			TINYINT
WITH RECOMPILE
AS
/*  Created: 20160302@Bravo
	Task : Report - Muay Thai Win Loss
	DB: DBEXT/bodb02
	Revisions: 
		- 20160302@Bravo: create sp on table sum 		
		- 20160322@Bravo: fix bug currency name VND => INH	
		- 20160412@Bruce: Add grand total in THB
		- 20171009@Harper: Get more info for MuayThai Parlay [Redmine: #82827]

	Param's Explanation:  
		- @TicketType: 1 - Single; 2 - Parlay; 3 - All		
*/
SET NOCOUNT ON
BEGIN	
	-- Region: Charge Info
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		IsDeposit   BIT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)
	DECLARE @ShareRate MONEY = 0.03

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 0)		
	)
	-- End region

	-- Region: Party List
	DECLARE @PartyList AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		BranchName	VARCHAR(100), 
		ParentId	INT
	)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel
		
	-- Endregion

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

	UPDATE #Exchange 
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51
	-- End region
	
	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
		LicenseeId	INT,
		PartyId		INT,
		rptDate		DATETIME,
		CurrencyId	INT,
		TotalTrans	INT,
		Turnover	MONEY,
		MemberWL	MONEY,
		WLShare		MONEY,
		LicComm		MONEY,
		CommShare	MONEY,
		AmtLicensee MONEY
	)

	-- Cut of date is 2017-10-01 - Just support single ticket
	DECLARE @CutOfDate		SMALLDATETIME,
			@TmpFromDate	SMALLDATETIME,
			@TmpToDate		SMALLDATETIME 

	SELECT @CutOfDate = '2017-09-30'
	SELECT @TmpFromDate = CASE WHEN @FromDate <= @CutOfDate THEN DATEADD(DAY,1,@CutOfDate) ELSE @FromDate END
	SELECT @TmpToDate = CASE WHEN @ToDate >= @CutOfDate THEN @CutOfDate ELSE @ToDate END

	IF @ToDate > @CutOfDate -- New Data
	BEGIN
		INSERT INTO #TempData (LicenseeId, PartyId, rptDate, CurrencyId, TotalTrans, Turnover, MemberWL, WLShare, LicComm, CommShare, AmtLicensee)
		(
			SELECT	b.SiteID,
					p.PartyId,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.Turnover, 0)) Turnover,
					SUM(ISNULL(b.AdjustedCustomerWL, 0)) MemberWL,
					SUM(ISNULL(b.AdjustedCustomerWL, 0) * - @ShareRate) WLShare,
					SUM(ISNULL(b.AdjustedCommissionS, 0)) LicComm,
					SUM(ISNULL(b.AdjustedCommShare, 0) * @ShareRate) CommShare,
					SUM(CASE WHEN p.IsDeposit = 0 
							THEN ISNULL(b.AdjustedLicenseeWL, 0) 
							ELSE ISNULL(-b.AdjustedCustomerWL, 0) * p.Rate 
						END) AmtLicensee
			FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
					INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
													AND b.SiteID = p.LicenseeId
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			WHERE	b.rptDate BETWEEN @TmpFromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN (27, 28)
					AND b.SportType = 44 -- MuayThai
					AND ( @TicketType = 3
						OR (@TicketType = 1 AND ISNULL(b.IsParlay, 0) = 0)
						OR (@TicketType = 2 AND ISNULL(b.IsParlay, 0) = 1)
						)
			GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
		)	
	END

	IF @FromDate <= @CutOfDate AND @TicketType IN (1, 3)-- Old data
	BEGIN
		INSERT INTO #TempData (LicenseeId, PartyId, rptDate, CurrencyId, TotalTrans, Turnover, MemberWL, WLShare, LicComm, CommShare, AmtLicensee)
		(
			SELECT	b.SiteID,
					p.PartyId,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.Turnover, 0)) Turnover,
					SUM(ISNULL(b.CustomerWL, 0)) MemberWL,
					SUM(ISNULL(b.WLShare, 0)) WLShare,
					SUM(ISNULL(b.CommissionS, 0)) LicComm,
					SUM(ISNULL(b.CommShare, 0)) CommShare,
					SUM(CASE WHEN p.IsDeposit = 0 
							THEN ISNULL(b.LicenseeWL, 0) 
							ELSE ISNULL(-b.CustomerWL, 0) * p.Rate 
						END) AmtLicensee
			FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
					INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
													AND b.SiteID = p.LicenseeId
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			WHERE	b.rptDate BETWEEN @FromDate AND @TmpToDate
					AND (b.CurrencyID <> 20)
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN (27, 28)
					AND b.SportType = 44 -- Muay Thai
			GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
		)
	END
	
	-- EndRegion
	
	-- Region: Result data
	CREATE TABLE #Result (
		PartyId				INT,
		PartyName			VARCHAR(100),
		ParentId			INT,
		ParentName			VARCHAR(100),
		WinLossDate			DATETIME,
		CurrencyName		VARCHAR(20),
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,		
		WinLossShare		MONEY,
		LicenseeComm		MONEY,
		CommissionShare		MONEY,
		AmountDueLicensee	MONEY,
		AmountDueMuayThai	MONEY,
		AmountDueCompany	MONEY
	)

	IF @BaseCurrencyName = ''
	BEGIN 
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, CommissionShare, AmountDueLicensee)
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode
			, SUM(td.TotalTrans)
			, SUM(td.Turnover)
			, SUM(td.MemberWL)
			, SUM(td.WLShare)
			, SUM(td.LicComm)
			, SUM(td.CommShare)
			, SUM(td.AmtLicensee)
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
		GROUP BY p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode
	END 
	ELSE 
	BEGIN
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, CommissionShare, AmountDueLicensee)
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode
			, SUM(td.TotalTrans)
			, SUM(td.Turnover*e.Rate)
			, SUM(td.MemberWL*e.Rate)
			, SUM(td.WLShare*e.Rate)
			, SUM(td.LicComm*e.Rate)
			, SUM(td.CommShare*e.Rate)
			, SUM(td.AmtLicensee*e.Rate)
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
		GROUP BY p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode
	END
	
	UPDATE #Result
	SET AmountDueMuayThai = WinLossShare + CommissionShare

	UPDATE #Result
	SET AmountDueCompany = AmountDueLicensee - AmountDueMuayThai
	-- EndRegion

	-- Region: Grand total data
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	-- support THB
	INSERT INTO @BaseCurrencies(Id, Name)VALUES(4,'THB')

	CREATE TABLE #GrandTotal (		
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss		MONEY,		
		WinLossShare		MONEY,
		LicenseeComm		MONEY,
		CommissionShare		MONEY,
		AmountDueLicensee	MONEY,
		AmountDueMuayThai	MONEY,
		AmountDueCompany	MONEY
	)
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)		
		DELETE FROM #Exchange
		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)

		INSERT INTO #GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,WinLossShare,LicenseeComm,CommissionShare,AmountDueLicensee)
		SELECT	@tempCurrency, 
				SUM(td.TotalTrans),
				SUM(td.Turnover*e.Rate), 
				SUM(td.MemberWL*e.Rate), 
				SUM(td.WLShare*e.Rate), 
				SUM(td.LicComm*e.Rate),
				SUM(td.CommShare*e.Rate),
				SUM(td.AmtLicensee*e.Rate)
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate				

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END

	UPDATE #GrandTotal
	SET AmountDueMuayThai = WinLossShare + CommissionShare

	UPDATE #GrandTotal
	SET AmountDueCompany = AmountDueLicensee - AmountDueMuayThai
	--EndRegion
	
	SELECT * FROM #Result
	SELECT * FROM #GrandTotal
	
	DROP TABLE #TempData
	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #GrandTotal
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO [vnteam] 
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_MuayThaiWinLoss] TO [bodbAdminNet]
GO
