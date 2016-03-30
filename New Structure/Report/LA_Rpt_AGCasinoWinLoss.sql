USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AGCasinoWinLoss]
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
/*  Created: 20160302@Bravo
	Task : Report - Muay Thai Win Loss
	DB: DBEXT/bodb02
	Revisions: 
		- 20160302@Bravo: create sp on table sum 		
		- 20160322@Bravo: fix bug currency name VND => INH	
	Param's Explanation:  						
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

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 0)
		--WHERE	DI_Rate > 0
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
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.StatusId BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.SportType = 44 -- Muay Thai
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
	)	
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
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover, td.MemberWL, td.WLShare, td.LicComm, td.CommShare, td.AmtLicensee
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
		
	END 
	ELSE 
	BEGIN
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, CommissionShare, AmountDueLicensee)
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover*e.Rate, td.MemberWL*e.Rate, td.WLShare*e.Rate, td.LicComm*e.Rate, td.CommShare*e.Rate, td.AmtLicensee*e.Rate
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
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
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO bodbAdminNet 