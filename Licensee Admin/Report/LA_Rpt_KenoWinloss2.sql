/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[LA_Rpt_KenoWinloss2]
	 @PartyIDs			VARCHAR(5500)
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@BaseCurrencyName	VARCHAR(10) = 'GBP'
AS
/*
 Created by	: [20160331@Bruce]
 Task		: Get Keno Winloss
 DB			: DBLIC.bodb_licensee

 Revisions:
	- 20160331@Bruce: #55003 - Support new Keno report
	- 20171219@Bruce: increase length for variables [#88197]
	- 20180515@Scofield: Incorporate 9wickets data [#94950]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180907@Parsons: Royalty fee updated for Keno& Lottery [#101168]
	- 20190716@Bruce: Integrate CN88 data in LA [#116859]
	- 20191216@Parsons: Modify pay to supplier's formula for Keno WL report [#125014]
	- 20191226@Mason: Set term by currency [#120005]
	- 20200219@Mason: Update RNG Keno term [#128563]

 Param's Explanation:
	- @FromDate		: From date
	- @ToDate		: To date
*/

BEGIN
	SET NOCOUNT ON

	-- Charge Info
	BEGIN
		DECLARE @PartyChargeInfo AS TABLE (
			ChargeId	INT,
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME
		)

		INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId,ProductID, Rate, Fromdate, Todate)
		(
			SELECT ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
			FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'KN', 'OA', 1)
			
			UNION
			
			-- get Credit settings with rate = 0
			SELECT ci.ChargeID, p.PartyID, lb.LabelID AS LicenseeID, ci.ProductId, ci.Rate, 
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
			FROM OAS_ChargeInfo ci WITH (NOLOCK)
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON ci.FromParty = p.PartyID AND ci.ChargeType != 2 AND p.PartyType = 1
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			LEFT JOIN dbo.labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
			WHERE ci.Productid = 8 and ci.Rate = 0 AND ISNULL(pd.IsDeposit, 0) = 0 AND
				p.PartyID IN (SELECT VAL FROM strSplit(@PartyIDs, ','))	AND
				(	@FromDate BETWEEN ci.FromDate AND ci.ToDate
					OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
					OR ci.FromDate BETWEEN @FromDate AND @ToDate
					OR ci.ToDate BETWEEN @FromDate AND @ToDate)
		)
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
		EXEC dbo.LA_PartyListSel

		-- This report has 3 group:
		--		- 12Bet: 12Bet
		--		- Credit: Credit licensees
		--		- ONEWorks: ONEWorks & Boping
		DECLARE	@12BetGroupId INT = -1,
				@OneWorksGroupId INT = 1,
				@CreditGroupId INT = 999,
				@CN88PartyId INT = (SELECT a.PartyID FROM dbo.OAS_Party a WITH(NOLOCK) WHERE a.PartyName='CN88'),
				@TianboPartyId INT = 432,
				@BobbetPartyId INT = 346
				
		UPDATE @PartyList SET PartyName = RTRIM(REPLACE(PartyName,'Licensees','')) WHERE ParentId = 0
		UPDATE @PartyList SET ParentId = @OneWorksGroupId WHERE ParentId IN (11,98)
		UPDATE @PartyList SET ParentId = @12BetGroupId WHERE PartyId = 14 -- 12bet

		INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
		SELECT @12BetGroupId, PartyName, BranchName, 0 FROM @PartyList WHERE PartyId = 14
	END

	-- Get Winloss data
	BEGIN
		CREATE TABLE #TempData (
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
			PayToSupplier	MONEY
		)

		;WITH SumByDate AS(
			SELECT	p.PartyId,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.Turnover, 0)) Turnover,
					SUM(ISNULL(b.MemberWL, 0)) MemberWL,
					SUM(ISNULL(-b.MemberWL, 0) * ISNULL(cr.Rate, p.Rate)) LicensingFee
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON (b.ProductID = p.ProductID) AND
											 (b.SiteID = p.LicenseeId) AND
											 (b.rptDate BETWEEN p.FromDate AND p.ToDate)
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = p.ChargeId AND cr.CurrencyID = b.CurrencyId
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					(b.CurrencyID <> 20) AND
					(b.customercategory NOT IN (27, 28)) AND
					 b.StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID
		)
		INSERT INTO #TempData (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT	p.PartyId,p.PartyName,g.PartyId,g.PartyName,s.rptDate,s.CurrencyId,s.TotalTrans,s.Turnover,s.MemberWL,-s.MemberWL,s.LicensingFee,
				(-s.MemberWL) * (CASE 
						WHEN p.PartyId = @CN88PartyId THEN 0.015
						WHEN p.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02
						WHEN g.PartyId IN (@CreditGroupId, @12BetGroupId) OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
						ELSE 0.05 
					END)
		FROM SumByDate s
		INNER JOIN @PartyList p ON s.PartyId = p.PartyID
		INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		-- Tianbo & Bobbet: 2%
		-- Credit licensees & 12Bet: 3% on Gross Win
		-- Other licenees: 5% on Gross Win
		-- CN88: 1.5% of winloss
	END

	-- Result data
	BEGIN
		CREATE TABLE #Result (
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			ParentName		VARCHAR(100),
			WinLossDate		DATETIME,
			CurrencyName	VARCHAR(10),
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY
		)

		IF(ISNULL(@BaseCurrencyName,'') = '')
		BEGIN
			INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT	td.PartyId,
					td.PartyName,
					td.ParentId,
					td.ParentName,
					td.WinLossDate,
					CASE WHEN e.Code = 'VND' THEN 'INH' 
						WHEN e.ExchangeID = 75 THEN 'PTU'
						WHEN e.ExchangeID = 76 THEN 'PS'
						WHEN e.ExchangeID = 77 THEN 'PTH'
						ELSE e.Code END AS CurrencyName,
					td.TotalTrans,
					td.Turnover,
					td.CustomerWinLoss,
					td.LicenseeWinLoss,
					td.LicensingFee,
					td.PayToSupplier,
					td.LicensingFee - td.PayToSupplier
			FROM #TempData td
			INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON td.CurrencyId = e.ExchangeID
		END
		ELSE
		BEGIN
			INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT	td.PartyId,
					td.PartyName,
					td.ParentId,
					td.ParentName,
					td.WinLossDate,
					CASE WHEN e.Code = 'VND' THEN 'INH' 
						WHEN e.ExchangeID = 75 THEN 'PTU'
						WHEN e.ExchangeID = 76 THEN 'PS'
						WHEN e.ExchangeID = 77 THEN 'PTH'
						ELSE e.Code END AS CurrencyName,
					td.TotalTrans,
					td.Turnover * e.BaseCurrencyRate,
					td.CustomerWinLoss * e.BaseCurrencyRate,
					td.LicenseeWinLoss * e.BaseCurrencyRate,
					td.LicensingFee * e.BaseCurrencyRate,
					td.PayToSupplier * e.BaseCurrencyRate,
					(td.LicensingFee - td.PayToSupplier) * e.BaseCurrencyRate
			FROM #TempData td
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.WinLossDate
		END
	END

	-- Calculate Total by group
	DECLARE @TotalByGroups AS TABLE(
		ParentId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CurrencyName	VARCHAR(10)
	)

	DECLARE @GrandTotal AS TABLE(
		CurrencyName	VARCHAR(10),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY
	)

	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT,
		RowIndex SMALLINT IDENTITY
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC dbo.LA_SelBaseCurrency

	-- Calculate Grand total
	BEGIN
		DECLARE @TempCurrency VARCHAR(10)

		WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
		BEGIN
			SET @TempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)

			;WITH SumByParty AS (
				SELECT	td.PartyId,
						td.ParentId,
						SUM(td.TotalTrans) TotalTrans,
						SUM(td.Turnover			* e.BaseCurrencyRate) Turnover,
						SUM(td.CustomerWinLoss	* e.BaseCurrencyRate) CustomerWinLoss,
						SUM(td.LicenseeWinLoss	* e.BaseCurrencyRate) LicenseeWinLoss,
						SUM(td.LicensingFee		* e.BaseCurrencyRate) LicensingFee,
						SUM(td.PayToSupplier	* e.BaseCurrencyRate) PayToSupplier
				FROM #TempData td
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @TempCurrency) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.WinLossDate
				GROUP BY td.ParentId,td.PartyId
			)
			INSERT INTO @TotalByGroups(ParentId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier, CurrencyName)
			SELECT	ParentId,
					SUM(TotalTrans),
					SUM(Turnover),
					SUM(CustomerWinLoss),
					SUM(LicenseeWinLoss),
					SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
					SUM(PayToSupplier),
					@TempCurrency
			FROM SumByParty
			GROUP BY ParentId

			UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @TempCurrency
		END

		INSERT INTO @GrandTotal(CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT	CurrencyName,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier)
		FROM @TotalByGroups
		GROUP BY CurrencyName
	END

	SELECT * FROM #Result

	SELECT	CurrencyName,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			(LicensingFee - PayToSupplier) CompanyIncome
	FROM @GrandTotal g
	INNER JOIN @BaseCurrencies b ON g.CurrencyName = b.Name
	ORDER BY b.RowIndex

	SELECT	ParentId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			(LicensingFee - PayToSupplier) CompanyIncome
	FROM @TotalByGroups
	WHERE CurrencyName = @BaseCurrencyName

	DROP TABLE #Result
	DROP TABLE #TempData
END
GO