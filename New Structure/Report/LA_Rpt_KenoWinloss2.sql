USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_KenoWinloss2]
	 @PartyIDs			VARCHAR(5500)
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@BaseCurrencyName	VARCHAR(3) = 'GBP'
AS
/*
 Created by	: [20160331@Bruce]
 Task		: Get Keno Winloss
 DB			: DB052.bodb_licensee

 Revisions:
	- 20160331@Bruce: #55003 - Support new Keno report

 Param's Explanation:
	- @FromDate		: From date
	- @ToDate		: To date
*/

BEGIN
	SET NOCOUNT ON

	-- Charge Info
	BEGIN
		DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME
		)

		INSERT INTO @PartyChargeInfo(PartyId, LicenseeId,ProductID, Rate, Fromdate, Todate)
		SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'KN', 'OA', 0)
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
		EXEC bodb_licensee.dbo.LA_PartyListSel

		-- This report has 3 group:
		--		- 12Bet: 12Bet
		--		- Credit: Credit licensees
		--		- ONEWorks: ONEWorks & Boping
		DECLARE	@12BetGroupId INT = -1,
				@OneWorksGroupId INT = 1,
				@CreditGroupId INT = 999

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
					SUM(ISNULL(-b.MemberWL, 0) * p.Rate) LicensingFee
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON (b.ProductID = p.ProductID) AND
											 (b.SiteID = p.LicenseeId) AND
											 (b.rptDate BETWEEN p.FromDate AND p.ToDate)
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					(b.CurrencyID <> 20) AND
					(b.customercategory NOT IN (27, 28)) AND
					 b.StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID
		)
		INSERT INTO #TempData (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT	p.PartyId,
				p.PartyName,
				g.PartyId,
				g.PartyName,
				s.rptDate,
				s.CurrencyId,
				s.TotalTrans,
				s.Turnover,
				s.MemberWL,
				-s.MemberWL,
				s.LicensingFee,
				(-s.MemberWL) * (CASE WHEN g.PartyId IN (999, -1) THEN 0.03 ELSE 0.05 END)
		FROM SumByDate s
		INNER JOIN @PartyList p ON s.PartyId = p.PartyID
		INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		-- Credit licensees & 12Bet: 3% on Gross Win
		-- Other licenees: 5% on Gross Win
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
					CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END AS CurrencyName,
					td.TotalTrans,
					td.Turnover,
					td.CustomerWinLoss,
					td.LicenseeWinLoss,
					td.LicensingFee,
					td.PayToSupplier,
					td.LicensingFee - td.PayToSupplier
			FROM #TempData td
			INNER JOIN bodb02.dbo.Exchange e ON td.CurrencyId = e.ExchangeID
		END
		ELSE
		BEGIN
			INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT	td.PartyId,
					td.PartyName,
					td.ParentId,
					td.ParentName,
					td.WinLossDate,
					CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END AS CurrencyName,
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
		CurrencyName	VARCHAR(3)
	)

	DECLARE @GrandTotal AS TABLE(
		CurrencyName	VARCHAR(3),
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
	EXEC bodb_Licensee.dbo.LA_SelBaseCurrency

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

		UPDATE @TotalByGroups SET PayToSupplier = CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END

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
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_KenoWinloss2] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_KenoWinloss2] TO bodbAdminNet