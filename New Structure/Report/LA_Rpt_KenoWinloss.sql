USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_KenoWinloss_xtest]
	 @PartyIDs			VARCHAR(5500)
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@BaseCurrencyName	VARCHAR(3) = 'GBP'
AS
/*
 Created by	: [20150303@Florent]
 Task		: Get Keno Winloss
 DB			: DB052.bodb02

 Revisions:
	- 20150320@Florent: enhance SP, using function LA_f_ExchangeDailySel
	- 20150705@Florent: add GBP
	- 20160331@Bruce: #55003 - Support new Keno report layout

 Param's Explanation:
	- @FromDate		: From date
	- @ToDate		: To date
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @HasBaseCurrency BIT = (CASE WHEN ISNULL(@BaseCurrencyName,'') <> '' THEN 1 ELSE 0 END)

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
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'KN', 'OA', 1)
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

		UPDATE @PartyList SET PartyName = RTRIM(REPLACE(PartyName,'Licensees',''))

		-- Create 12bet group
		UPDATE @PartyList SET ParentId = -1 WHERE PartyId = 14 -- 12bet

		INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
		SELECT -1, PartyName, BranchName, 0 FROM @PartyList WHERE PartyId = 14 -- 12bet
	END

	-- Get Winloss data
	BEGIN
		CREATE TABLE #TempData (
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			MemberWL		MONEY,
			LicensingFee	MONEY
		)

		INSERT INTO #TempData (PartyId,rptDate,CurrencyId,TotalTrans,Turnover,MemberWL,LicensingFee)
		(
			SELECT	p.PartyId,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)),
					SUM(ISNULL(b.Turnover, 0)),
					SUM(ISNULL(b.MemberWL, 0)),
					SUM(ISNULL(-b.MemberWL, 0) * p.Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON (b.ProductID = p.ProductID) AND
											 (b.SiteID = p.LicenseeId) AND
											 (b.rptDate BETWEEN p.FromDate AND p.ToDate)
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					(b.CurrencyID <> 20) AND
					(b.customercategory NOT IN (27, 28))
			GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID, b.ProductId
		)
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
			CustomerWL		MONEY,
			LicenseeWL		MONEY,
			LicensingFee	MONEY
		)

		IF(@HasBaseCurrency = 0)
		BEGIN
			SELECT	p.PartyId,
					p.PartyName,
					g.PartyId AS ParentId,
					g.PartyName AS ParentName,
					td.rptDate AS WinLossDate,
					CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END AS CurrencyName,
					td.TotalTrans,
					td.Turnover,
					td.MemberWL AS CustomerWL,
					-td.MemberWL AS LicenseeWL,
					NULL AS LicensingFee
			FROM #TempData td
			INNER JOIN bodb02.dbo.Exchange e ON td.CurrencyId = e.ExchangeID
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList g ON p.ParentId = g.PartyId

			SET @BaseCurrencyName = 'GBP'
		END

		-- Convert base currency
		INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWL,LicenseeWL,LicensingFee)
		SELECT	p.PartyId,
				p.PartyName,
				g.PartyId,
				g.PartyName,
				td.rptDate,
				CASE WHEN e.Code = 'VND' THEN 'INH' ELSE e.Code END AS CurrencyName,
				td.TotalTrans,
				td.Turnover		* e.BaseCurrencyRate,
				td.MemberWL		* e.BaseCurrencyRate,
				-td.MemberWL	* e.BaseCurrencyRate,
				td.LicensingFee	* e.BaseCurrencyRate
		FROM #TempData td
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
		INNER JOIN @PartyList g ON p.ParentId = g.PartyId

		IF(@HasBaseCurrency = 1) SELECT * FROM #Result
	END

	-- Calculate Total by group
	BEGIN
		DECLARE @TotalByGroups AS TABLE(
			GroupId			INT,
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWL		MONEY,
			LicenseeWL		MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY
		)

		;WITH SumByParty AS (
			SELECT	r.ParentId AS GroupId,
					r.PartyId,
					SUM(r.TotalTrans) TotalTrans,
					SUM(r.Turnover) Turnover,
					SUM(r.CustomerWL) CustomerWL,
					SUM(r.LicenseeWL) LicenseeWL,
					SUM(r.LicensingFee) LicensingFee
			FROM #Result r
			GROUP BY r.ParentId, r.PartyId
		)
		INSERT INTO @TotalByGroups(GroupId,TotalTrans,Turnover,CustomerWL,LicenseeWL,LicensingFee)
		SELECT	GroupId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWL),
				SUM(LicenseeWL),
				SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END)
		FROM SumByParty
		GROUP BY GroupId

		-- Credit licensees & 12Bet: 3% on Gross Win
		-- Other licenees: 5% on Gross Win
		UPDATE @TotalByGroups
		SET PayToSupplier =	CASE
								WHEN LicenseeWL < 0 THEN 0
								ELSE LicenseeWL * (CASE WHEN GroupId IN (999, -1) THEN 0.03 ELSE 0.05 END)
							END

		SELECT	GroupId,
				TotalTrans,
				Turnover,
				CustomerWL,
				LicenseeWL,
				LicensingFee,
				PayToSupplier,
				(LicensingFee - PayToSupplier) CompanyIncome
		FROM @TotalByGroups
	END

	-- Calculate Grand total
	BEGIN
		DECLARE @BaseCurrencyId INT
		DECLARE @tempCurrency VARCHAR(10)
		DECLARE @Rate FLOAT

		-- base currencies
		DECLARE @BaseCurrencies TABLE(
			Id INT,
			Name VARCHAR(20),
			IsApply BIT
		)
		INSERT INTO @BaseCurrencies(Id, Name)
		EXEC bodb_Licensee.dbo.LA_SelBaseCurrency

		SET @BaseCurrencyId = (SELECT Id FROM @BaseCurrencies WHERE Name = @BaseCurrencyName)

		-- grand total
		DECLARE @GrandTotal AS TABLE(
			CurrencyName	VARCHAR(3),
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWL		MONEY,
			LicenseeWL		MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY
		)

		-- sum total to grand total
		INSERT INTO @GrandTotal(CurrencyName,TotalTrans,Turnover,CustomerWL,LicenseeWL,LicensingFee,PayToSupplier)
		SELECT	@BaseCurrencyName,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWL),
				SUM(LicenseeWL),
				SUM(LicensingFee),
				SUM(PayToSupplier)
		FROM @TotalByGroups

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @BaseCurrencyName

		WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
			SET @Rate = (SELECT BaseCurrencyRate FROM bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @tempCurrency) WHERE ExchangeId = @BaseCurrencyId)

			INSERT INTO @GrandTotal(CurrencyName,TotalTrans,Turnover,CustomerWL,LicenseeWL,LicensingFee,PayToSupplier)
			SELECT	@tempCurrency,
					SUM(TotalTrans),
					SUM(Turnover * @Rate),
					SUM(CustomerWL * @Rate),
					SUM(LicenseeWL * @Rate),
					SUM(LicensingFee * @Rate),
					SUM(PayToSupplier * @Rate)
			FROM @TotalByGroups

			UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
		END

		SELECT CurrencyName,
				TotalTrans,
				Turnover,
				CustomerWL,
				LicenseeWL,
				LicensingFee,
				PayToSupplier,
				(LicensingFee - PayToSupplier) CompanyIncome
		FROM @GrandTotal
	END

	DROP TABLE #Result
	DROP TABLE #TempData
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_KenoWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_KenoWinloss] TO bodbAdminNet